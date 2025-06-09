defmodule TestTools.NestedFieldTool do
  @moduledoc "Tool with nested field definitions"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :name, {:required, :string}, description: "Full name"

    field :address, description: "Mailing address" do
      field :street, {:required, :string}
      field :city, {:required, :string}
      field :state, :string
      field :zip, :string, format: "postal-code"
    end

    field :contact do
      field :email, :string, format: "email", description: "Contact email"
      field :phone, :string, format: "phone"
    end
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.text(Response.tool(), "it doesnt matter"), frame}
  end
end

defmodule TestTools.SingleNestedFieldTool do
  @moduledoc "Tool with single nested field"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :user, description: "User information" do
      field :id, {:required, :string}, format: "uuid"
    end
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.text(Response.tool(), "doesnt matter"), frame}
  end
end

defmodule TestTools.DeeplyNestedTool do
  @moduledoc "Tool with deeply nested fields"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    field :organization do
      field :name, {:required, :string}

      field :admin, description: "Organization admin" do
        field :name, {:required, :string}

        field :permissions do
          field :read, {:required, :boolean}
          field :write, {:required, :boolean}
          field :delete, :boolean
        end
      end
    end
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.text(Response.tool(), "doesnt matter"), frame}
  end
end

defmodule TestTools.LegacyTool do
  @moduledoc "Tool using traditional Peri schema syntax without field macros"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  schema do
    %{
      name: {:required, :string},
      age: {:integer, {:default, 25}},
      email: :string,
      tags: {:list, :string},
      metadata: %{
        created_at: :string,
        updated_at: :string
      }
    }
  end

  @impl true
  def execute(_params, frame) do
    {:reply, Response.text(Response.tool(), "doesnt matter"), frame}
  end
end

defmodule TestPrompts.FieldPrompt do
  @moduledoc "Test prompt with field metadata"

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Response

  schema do
    field :code, {:required, :string}, description: "The code to review"
    field :language, {:required, :string}, description: "Programming language"
    field :focus_areas, :string, description: "Areas to focus on (optional)"
  end

  @impl true
  def get_messages(_params, frame) do
    {:reply, Response.user_message(Response.prompt(), "hello"), frame}
  end
end

defmodule TestPrompts.NestedPrompt do
  @moduledoc "Prompt with nested fields"

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Response

  schema do
    field :config, description: "Configuration options" do
      field :model, {:required, :string}, description: "Model to use"
      field :temperature, :float, description: "Temperature setting"
    end
  end

  @impl true
  def get_messages(_params, frame) do
    {:reply, Response.user_message(Response.prompt(), "hello"), frame}
  end
end

defmodule TestPrompts.LegacyPrompt do
  @moduledoc "Legacy prompt without field macros"

  use Hermes.Server.Component, type: :prompt

  alias Hermes.Server.Response

  schema do
    %{
      query: {:required, :string},
      max_results: {:integer, {:default, 10}}
    }
  end

  @impl true
  def get_messages(_params, frame) do
    {:reply, Response.user_message(Response.prompt(), "hello"), frame}
  end
end
