defmodule Hermes.Server.Component do
  @moduledoc false

  alias Hermes.Server.Component.Prompt
  alias Hermes.Server.Component.Resource
  alias Hermes.Server.Component.Tool

  @doc false
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro __using__(opts) when is_list(opts) do
    {type, opts} = Keyword.pop!(opts, :type)

    if type not in [:tool, :prompt, :resource] do
      raise ArgumentError,
            "Invalid component type: #{type}. Must be :tool, :prompt, or :resource"
    end

    behaviour_module = get_behaviour_module(type)

    uri = Keyword.get(opts, :uri)
    mime_type = Keyword.get(opts, :mime_type, "text/plain")
    annotations = Keyword.get(opts, :annotations)

    quote do
      @behaviour unquote(behaviour_module)

      import Hermes.Server.Component,
        only: [
          schema: 1,
          output_schema: 1,
          field: 3,
          field: 2,
          embeds_many: 3,
          embeds_many: 2,
          embeds_one: 3,
          embeds_one: 2
        ]

      import Hermes.Server.Frame

      @doc false
      def __mcp_component_type__, do: unquote(type)

      @doc false
      def __description__, do: @moduledoc

      if unquote(type) == :tool do
        @impl true
        def input_schema do
          alias Hermes.Server.Component.Schema

          Schema.to_json_schema(__mcp_raw_schema__())
        end

        if unquote(annotations) != nil do
          @impl true
          def annotations, do: unquote(annotations)
        end
      end

      if unquote(type) == :prompt do
        @impl true
        def arguments do
          alias Hermes.Server.Component.Schema

          Schema.to_prompt_arguments(__mcp_raw_schema__())
        end
      end

      if unquote(type) == :resource do
        @impl true
        def uri, do: unquote(uri)

        @impl true
        def mime_type, do: unquote(mime_type)

        defoverridable uri: 0, mime_type: 0
      end
    end
  end

  @doc """
  Defines the parameter schema for the component.

  The schema uses Peri's validation DSL and is automatically validated
  before the component's callback is executed.
  """
  defmacro schema(do: schema_def) do
    wrapped_schema =
      case schema_def do
        {:%{}, _, _} = map_ast ->
          map_ast

        {:__block__, _, field_calls} ->
          {:%{}, [], field_calls}

        single_field ->
          {:%{}, [], [single_field]}
      end

    quote do
      import Peri

      alias Hermes.Server.Component

      @doc false
      def __mcp_raw_schema__, do: unquote(wrapped_schema)

      defschema(
        :mcp_schema,
        Component.__clean_schema_for_peri__(unquote(wrapped_schema))
      )
    end
  end

  @doc """
  Defines the output schema for a tool component.

  This schema describes the expected structure of the tool's output in the
  structuredContent field. Only available for tool components.
  """
  defmacro output_schema(do: schema_def) do
    wrapped_schema =
      case schema_def do
        {:%{}, _, _} = map_ast ->
          map_ast

        {:__block__, _, field_calls} ->
          {:%{}, [], field_calls}

        single_field ->
          {:%{}, [], [single_field]}
      end

    quote do
      import Peri

      alias Hermes.Server.Component

      @doc false
      def __mcp_output_schema__, do: unquote(wrapped_schema)

      defschema(
        :mcp_output_schema,
        Component.__clean_schema_for_peri__(unquote(wrapped_schema))
      )

      @impl true
      def output_schema do
        alias Hermes.Server.Component.Schema

        Schema.to_json_schema(__mcp_output_schema__())
      end
    end
  end

  @doc """
  Defines a field with metadata for JSON Schema generation.

  Supports both simple fields and nested objects with their own fields.

  ## Examples

      # Simple field
      field :email, {:required, :string}, format: "email", description: "User's email address"
      field :age, :integer, description: "Age in years"
      
      # Nested field
      field :user do
        field :name, {:required, :string}
        field :email, :string, format: "email"
      end

      # Nested field with metadata
      field :profile, description: "User profile information" do
        field :bio, :string, description: "Short biography"
        field :avatar_url, :string, format: "uri"
      end
  """
  defmacro field(name, type \\ nil, opts \\ [])

  defmacro field(name, opts, do: block) when is_list(opts) and opts != [] do
    build_nested_field(name, opts, block)
  end

  defmacro field(name, nil, do: block) do
    build_nested_field(name, [], block)
  end

  defmacro field(name, [do: block], []) do
    build_nested_field(name, [], block)
  end

  defmacro field(name, type, opts) when not is_nil(type) and is_list(opts) do
    {required, remaining_opts} = Keyword.pop(opts, :required, false)
    type = if required, do: {:required, type}, else: type

    quote do
      {unquote(name), {:mcp_field, unquote(type), unquote(remaining_opts)}}
    end
  end

  defp build_nested_field(name, opts, block) do
    nested_content =
      case block do
        {:__block__, _, expressions} ->
          {:%{}, [], expressions}

        single_expr ->
          {:%{}, [], [single_expr]}
      end

    quote do
      {unquote(name), {:mcp_field, unquote(nested_content), unquote(opts)}}
    end
  end

  @doc """
  Defines a field that embeds many objects (array of objects).

  ## Examples

      embeds_many :users, description: "List of users" do
        field :id, :string, required: true, description: "User ID"
        field :name, :string, description: "User name"
      end

      embeds_many :tags, required: true do
        field :name, :string, required: true
        field :value, :string
      end
  """
  defmacro embeds_many(name, opts \\ [], do: block) do
    {required, remaining_opts} = Keyword.pop(opts, :required, false)

    nested_content =
      case block do
        {:__block__, _, expressions} ->
          {:%{}, [], expressions}

        single_expr ->
          {:%{}, [], [single_expr]}
      end

    type = if required, do: {:required, {:list, nested_content}}, else: {:list, nested_content}

    quote do
      {unquote(name), {:mcp_field, unquote(type), unquote(remaining_opts)}}
    end
  end

  @doc """
  Defines a field that embeds one object.

  ## Examples

      embeds_one :user, description: "User object" do
        field :id, :string, required: true, description: "User ID"
        field :name, :string, description: "User name"
      end

      embeds_one :address, required: true do
        field :street, :string, required: true
        field :city, :string, required: true
        field :zip, :string
      end
  """
  defmacro embeds_one(name, opts \\ [], do: block) do
    {required, remaining_opts} = Keyword.pop(opts, :required, false)

    nested_content =
      case block do
        {:__block__, _, expressions} ->
          {:%{}, [], expressions}

        single_expr ->
          {:%{}, [], [single_expr]}
      end

    type = if required, do: {:required, nested_content}, else: nested_content

    quote do
      {unquote(name), {:mcp_field, unquote(type), unquote(remaining_opts)}}
    end
  end

  defp get_behaviour_module(:tool), do: Tool
  defp get_behaviour_module(:prompt), do: Prompt
  defp get_behaviour_module(:resource), do: Resource

  @doc """
  Extracts the description from a component module's moduledoc.

  ## Parameters
    * `module` - The component module atom

  ## Returns
    * The module's `@moduledoc` content as a string
    * Empty string if no moduledoc is defined

  ## Examples

      iex> defmodule MyTool do
      ...>   @moduledoc "A helpful tool"
      ...>   use Hermes.Server.Component, type: :tool
      ...> end
      iex> Hermes.Server.Component.get_description(MyTool)
      "A helpful tool"
  """
  def get_description(module) when is_atom(module) do
    if function_exported?(module, :__description__, 0) do
      module.__description__()
    else
      ""
    end
  end

  @doc """
  Gets the component type (:tool, :prompt, or :resource).

  ## Parameters
    * `module` - The component module atom

  ## Returns
    * `:tool` - If the module is a tool component
    * `:prompt` - If the module is a prompt component
    * `:resource` - If the module is a resource component

  ## Examples

      iex> defmodule MyTool do
      ...>   use Hermes.Server.Component, type: :tool
      ...> end
      iex> Hermes.Server.Component.get_type(MyTool)
      :tool
  """
  def get_type(module) when is_atom(module) do
    module.__mcp_component_type__()
  end

  @doc """
  Checks if a module is a valid component.

  ## Parameters
    * `module` - The module atom to check

  ## Returns
    * `true` if the module uses `Hermes.Server.Component`
    * `false` otherwise

  ## Examples

      iex> defmodule MyTool do
      ...>   use Hermes.Server.Component, type: :tool
      ...> end
      iex> Hermes.Server.Component.component?(MyTool)
      true

      iex> defmodule NotAComponent do
      ...>   def hello, do: :world
      ...> end
      iex> Hermes.Server.Component.component?(NotAComponent)
      false
  """
  def component?(module) when is_atom(module) do
    not is_nil(get_type(module))
  end

  @doc false
  def __clean_schema_for_peri__(schema) when is_map(schema) do
    Map.new(schema, fn
      {key, {:mcp_field, type, _opts}} -> {key, __clean_schema_for_peri__(type)}
      {key, nested} when is_map(nested) -> {key, __clean_schema_for_peri__(nested)}
      {key, value} -> {key, __inject_transforms__(value)}
    end)
  end

  def __clean_schema_for_peri__(schema), do: __inject_transforms__(schema)

  defp __inject_transforms__({type, {:default, default}}) when type in ~w(date datetime naive_datetime time)a do
    base = __inject_transforms__(type)
    {base, {:default, default}}
  end

  defp __inject_transforms__(:date) do
    {:custom, &__validate_date__/1}
  end

  defp __inject_transforms__(:time) do
    {:custom, &__validate_time__/1}
  end

  defp __inject_transforms__(:datetime) do
    {:custom, &__validate_datetime__/1}
  end

  defp __inject_transforms__(:naive_datetime) do
    {:custom, &__validate_naive_datetime__/1}
  end

  defp __inject_transforms__({:required, type}) do
    {:required, __inject_transforms__(type)}
  end

  defp __inject_transforms__({:list, type}) do
    {:list, __inject_transforms__(type)}
  end

  defp __inject_transforms__(nested) when is_map(nested) do
    __clean_schema_for_peri__(nested)
  end

  defp __inject_transforms__(type), do: type

  defp __validate_date__(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _} -> {:error, "invalid ISO 8601 date format", []}
    end
  end

  defp __validate_date__(%Date{} = date), do: {:ok, date}

  defp __validate_date__(_), do: {:error, "expected ISO 8601 date string or Date struct", []}

  defp __validate_time__(value) when is_binary(value) do
    case Time.from_iso8601(value) do
      {:ok, time} -> {:ok, time}
      {:error, _} -> {:error, "invalid ISO 8601 time format", []}
    end
  end

  defp __validate_time__(%Time{} = time), do: {:ok, time}

  defp __validate_time__(_), do: {:error, "expected ISO 8601 time string or Time struct", []}

  defp __validate_datetime__(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> {:ok, datetime}
      {:error, _} -> {:error, "invalid ISO 8601 datetime format", []}
    end
  end

  defp __validate_datetime__(%DateTime{} = datetime), do: {:ok, datetime}

  defp __validate_datetime__(_), do: {:error, "expected ISO 8601 datetime string or DateTime struct", []}

  defp __validate_naive_datetime__(value) when is_binary(value) do
    # NaiveDateTime.from_iso8601 accepts Z suffix but we want to reject it
    if String.ends_with?(value, "Z") or String.match?(value, ~r/[+-]\d{2}:\d{2}$/) do
      {:error, "NaiveDateTime cannot have timezone information", []}
    else
      case NaiveDateTime.from_iso8601(value) do
        {:ok, naive_datetime} -> {:ok, naive_datetime}
        {:error, _} -> {:error, "invalid ISO 8601 naive datetime format", []}
      end
    end
  end

  defp __validate_naive_datetime__(%NaiveDateTime{} = naive_datetime), do: {:ok, naive_datetime}

  defp __validate_naive_datetime__(_), do: {:error, "expected ISO 8601 naive datetime string or NaiveDateTime struct", []}
end
