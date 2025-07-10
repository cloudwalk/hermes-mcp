defmodule Hermes.Client.RequestHandler do
  @moduledoc false

  use Hermes.Logging

  alias Hermes.Client.Operation
  alias Hermes.Client.Request
  alias Hermes.Client.State
  alias Hermes.MCP.Error
  alias Hermes.MCP.Message
  alias Hermes.MCP.Response
  alias Hermes.Telemetry

  require Message

  @spec execute_request(
          State.t(),
          Operation.t(),
          transport :: map(),
          from :: GenServer.from()
        ) ::
          {:ok, State.t()} | {:error, Error.t()}
  def execute_request(state, operation, transport, from) do
    method = operation.method
    params = operation.params

    params_with_token =
      State.add_progress_token_to_params(params, operation.progress_opts)

    with :ok <- State.validate_capability(state, method),
         {request_id, updated_state} =
           State.add_request_from_operation(state, operation, from),
         {:ok, request_data} <- encode_request(method, params_with_token, request_id),
         :ok <- send_transport_message(transport, request_data) do
      Telemetry.execute(
        Telemetry.event_client_request(),
        %{system_time: System.system_time()},
        %{method: method, request_id: request_id}
      )

      {:ok, updated_state}
    else
      {:error, _} = error -> error
    end
  end

  @spec execute_batch(
          State.t(),
          [Operation.t()],
          transport :: map(),
          from :: GenServer.from(),
          batch_id :: String.t()
        ) ::
          {:ok, State.t()} | {:error, Error.t()}
  def execute_batch(state, operations, transport, from, batch_id) do
    with :ok <- validate_batch_operations(state, operations),
         {batch_messages, state} <-
           prepare_batch_messages(state, operations, from, batch_id),
         {:ok, batch_data} <- Message.encode_batch(batch_messages),
         :ok <- send_transport_message(transport, batch_data) do
      Logging.client_event("batch_request_sent", %{
        size: length(operations),
        methods: Enum.map(operations, & &1.method)
      })

      {:ok, state}
    else
      {:error, _} = error -> error
    end
  end

  @spec handle_response(State.t(), map()) :: State.t()
  def handle_response(state, %{"id" => id} = response)
      when Message.is_response(response) do
    handle_success_response(response, id, state)
  end

  def handle_response(state, %{"id" => id} = response) when Message.is_error(response) do
    handle_error_response(response, id, state)
  end

  def handle_response(state, _response) do
    Logging.client_event("unknown_response_type", %{}, level: :warning)
    state
  end

  @spec handle_batch_response(State.t(), [map()], batch_id :: String.t()) :: State.t()
  def handle_batch_response(state, responses, batch_id) do
    {results, updated_state} = collect_batch_results(responses, state)

    case get_batch_from(batch_id, updated_state) do
      {:ok, from} ->
        if State.batch_complete?(updated_state, batch_id) do
          formatted_results = format_batch_results(results)
          GenServer.reply(from, {:ok, formatted_results})
        end

        updated_state

      :error ->
        Logging.client_event("unknown_batch", %{batch_id: batch_id}, level: :warning)
        updated_state
    end
  end

  @spec handle_timeout(State.t(), request_id :: String.t()) :: State.t()
  def handle_timeout(state, request_id) do
    case State.remove_request(state, request_id) do
      {nil, state} ->
        state

      {request, updated_state} ->
        elapsed_ms = Request.elapsed_time(request)

        Logging.client_event("request_timeout", %{
          id: request_id,
          method: request.method,
          elapsed_ms: elapsed_ms
        })

        Telemetry.execute(
          Telemetry.event_client_error(),
          %{duration: elapsed_ms, system_time: System.system_time()},
          %{
            id: request_id,
            method: request.method,
            error: :timeout
          }
        )

        if is_nil(request.batch_id) do
          GenServer.reply(
            request.from,
            {:error,
             Error.transport(:timeout, %{
               method: request.method,
               elapsed_ms: elapsed_ms
             })}
          )
        end

        updated_state
    end
  end

  defp encode_request(method, params, request_id) do
    request = %{"method" => method, "params" => params}
    Logging.message("outgoing", "request", request_id, request)
    Message.encode_request(request, request_id)
  end

  defp prepare_batch_messages(state, operations, from, batch_id) do
    {messages, final_state} =
      Enum.map_reduce(operations, state, fn operation, acc_state ->
        params_with_token =
          State.add_progress_token_to_params(operation.params, operation.progress_opts)

        {request_id, updated_state} =
          State.add_request_from_operation(acc_state, operation, from, batch_id)

        message = %{
          "jsonrpc" => "2.0",
          "method" => operation.method,
          "params" => params_with_token,
          "id" => request_id
        }

        {message, updated_state}
      end)

    {messages, final_state}
  end

  defp validate_batch_operations(state, operations) do
    Enum.reduce_while(operations, :ok, fn operation, :ok ->
      case State.validate_capability(state, operation.method) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp handle_success_response(%{"id" => id, "result" => result}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        Logging.client_event("unknown_response", %{id: id})
        state

      {request, updated_state} ->
        process_successful_response(request, result, id, updated_state)
    end
  end

  defp handle_error_response(%{"error" => json_error, "id" => id}, id, state) do
    case State.remove_request(state, id) do
      {nil, state} ->
        log_unknown_error_response(id, json_error)
        state

      {request, updated_state} ->
        process_error_response(request, json_error, id, updated_state)
    end
  end

  defp process_successful_response(request, result, id, state) do
    elapsed_ms = Request.elapsed_time(request)

    log_success_response(request, id, elapsed_ms)

    if is_nil(request.batch_id) do
      case request.method do
        "ping" ->
          GenServer.reply(request.from, :pong)

        _ ->
          response = Response.from_json_rpc(%{"result" => result})
          response_with_method = %{response | method: request.method}
          GenServer.reply(request.from, {:ok, response_with_method})
      end
    end

    state
  end

  defp process_error_response(request, json_error, id, state) do
    error = Error.from_json_rpc(json_error)
    elapsed_ms = Request.elapsed_time(request)

    log_error_response(request, id, elapsed_ms, json_error)

    if is_nil(request.batch_id) do
      GenServer.reply(request.from, {:error, error})
    end

    state
  end

  defp log_success_response(request, id, elapsed_ms) do
    Logging.client_event("success_response", %{id: id, method: request.method})

    Telemetry.execute(
      Telemetry.event_client_response(),
      %{duration: elapsed_ms, system_time: System.system_time()},
      %{
        id: id,
        method: request.method,
        status: :success
      }
    )
  end

  defp log_error_response(request, id, elapsed_ms, json_error) do
    Logging.client_event("error_response", %{
      id: id,
      method: request.method
    })

    Telemetry.execute(
      Telemetry.event_client_error(),
      %{duration: elapsed_ms, system_time: System.system_time()},
      %{
        id: id,
        method: request.method,
        error_code: json_error["code"],
        error_message: json_error["message"]
      }
    )
  end

  defp log_unknown_error_response(id, json_error) do
    Logging.client_event("unknown_error_response", %{
      id: id,
      code: json_error["code"],
      message: json_error["message"]
    })
  end

  defp collect_batch_results(messages, state) do
    Enum.reduce(messages, {%{}, state}, fn message, {results, current_state} ->
      case message do
        %{"id" => id} = msg when Message.is_error(msg) ->
          {_request, new_state} = State.remove_request(current_state, id)
          error = Error.from_json_rpc(msg["error"])
          {Map.put(results, id, {:error, error}), new_state}

        %{"id" => id} = msg when Message.is_response(msg) ->
          {request, new_state} = State.remove_request(current_state, id)
          response = Response.from_json_rpc(msg)
          response_with_method = %{response | method: request && request.method}
          {Map.put(results, id, {:ok, response_with_method}), new_state}

        _ ->
          {results, current_state}
      end
    end)
  end

  defp get_batch_from(batch_id, state) do
    case State.get_batch_requests(state, batch_id) do
      [request | _] -> {:ok, request.from}
      [] -> :error
    end
  end

  defp format_batch_results(results) do
    results
    |> Map.values()
    |> Enum.map(fn
      {:ok, %Response{method: "ping"} = resp} -> {:ok, %{resp | result: :pong}}
      {:ok, %Response{} = response} -> {:ok, response}
      {:error, _} = error -> error
    end)
  end

  defp send_transport_message(transport, data) do
    with {:error, reason} <- transport.layer.send_message(transport.name, data) do
      {:error, Error.transport(:send_failure, %{original_reason: reason})}
    end
  end
end
