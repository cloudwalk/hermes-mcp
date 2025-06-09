defmodule TestTools.NestedFieldTool do
  @moduledoc "Tool with nested field definitions"

  use Hermes.Server.Component, type: :tool

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
    {:reply, %{success: true}, frame}
  end
end

defmodule TestTools.SingleNestedFieldTool do
  @moduledoc "Tool with single nested field"

  use Hermes.Server.Component, type: :tool

  schema do
    field :user, description: "User information" do
      field :id, {:required, :string}, format: "uuid"
    end
  end

  @impl true
  def execute(_params, frame) do
    {:reply, %{success: true}, frame}
  end
end

defmodule TestTools.DeeplyNestedTool do
  @moduledoc "Tool with deeply nested fields"

  use Hermes.Server.Component, type: :tool

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
    {:reply, %{success: true}, frame}
  end
end

defmodule TestTools.LegacyTool do
  @moduledoc "Tool using traditional Peri schema syntax without field macros"

  use Hermes.Server.Component, type: :tool

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
    {:reply, %{success: true}, frame}
  end
end
