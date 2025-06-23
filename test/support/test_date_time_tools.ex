defmodule TestTools.DateTool do
  @moduledoc "Tool with date field"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :event_date, :date, required: true, description: "Event date"
    field :optional_date, :date, description: "Optional date"
  end

  @impl true
  def execute(%{event_date: date}, frame) do
    {:reply, Response.text(Response.tool(), "Date received: #{date}"), frame}
  end
end

defmodule TestTools.DateTimeTool do
  @moduledoc "Tool with datetime field"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :created_at, :datetime, required: true, description: "Creation timestamp"
    field :updated_at, :datetime, description: "Update timestamp"
  end

  @impl true
  def execute(%{created_at: datetime}, frame) do
    {:reply, Response.text(Response.tool(), "DateTime: #{datetime}"), frame}
  end
end

defmodule TestTools.TimeTool do
  @moduledoc "Tool with time field"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :start_time, :time, required: true, description: "Start time"
  end

  @impl true
  def execute(%{start_time: time}, frame) do
    {:reply, Response.text(Response.tool(), "Time: #{time}"), frame}
  end
end

defmodule TestTools.NaiveDateTimeTool do
  @moduledoc "Tool with naive datetime field"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :timestamp, :naive_datetime, required: true
  end

  @impl true
  def execute(%{timestamp: ndt}, frame) do
    {:reply, Response.text(Response.tool(), "NaiveDateTime: #{ndt}"), frame}
  end
end

defmodule TestTools.EventTool do
  @moduledoc "Tool with nested date fields"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :event, required: true do
      field :name, :string, required: true
      field :date, :date, required: true
      field :start_time, :time, required: true
    end
  end

  @impl true
  def execute(%{event: _event}, frame) do
    {:reply, Response.text(Response.tool(), "Event processed"), frame}
  end
end

defmodule TestTools.DateListTool do
  @moduledoc "Tool with list of dates"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :important_dates, {:list, :date}, required: true
  end

  @impl true
  def execute(%{important_dates: _dates}, frame) do
    {:reply, Response.text(Response.tool(), "Dates processed"), frame}
  end
end

defmodule TestTools.RequiredOptionTool do
  @moduledoc "Tool demonstrating required: true option"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :birth_date, :date, required: true, description: "Date of birth"
    field :expiry_date, :date, description: "Expiration date"
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.text(Response.tool(), "Processed"), frame}
  end
end
