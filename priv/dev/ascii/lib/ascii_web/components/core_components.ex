defmodule AsciiWeb.CoreComponents do
  @moduledoc """
  Core UI components for ASCII Art Studio.
  """

  use Phoenix.Component

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in your `assets/tailwind.config.js`.

  ## Examples

      <.icon name="hero-x-mark-solid" />
      <.icon name="hero-arrow-path" class="ml-1 w-3 h-3 animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a glass panel with backdrop blur effect.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def glass_panel(assigns) do
    ~H"""
    <div class={[
      "bg-gray-800/50 backdrop-blur-md rounded-2xl shadow-2xl p-8 border border-gray-700",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a gradient button.
  """
  attr :type, :string, default: "button"
  attr :variant, :string, default: "primary"
  attr :disabled, :boolean, default: false
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(form name value phx-click phx-submit)
  slot :inner_block, required: true

  def gradient_button(assigns) do
    assigns = assign(assigns, :classes, button_classes(assigns.variant, assigns.disabled))

    ~H"""
    <button type={@type} disabled={@disabled} class={[@classes, @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_classes("primary", true),
    do:
      "px-6 py-3 bg-gradient-to-r from-gray-600 to-gray-700 text-white font-medium rounded-lg cursor-not-allowed transform transition-all duration-200 scale-100"

  defp button_classes("primary", false),
    do:
      "px-6 py-3 bg-gradient-to-r from-purple-600 to-pink-600 text-white font-medium rounded-lg hover:from-purple-700 hover:to-pink-700 transform transition-all duration-200 hover:scale-105"

  defp button_classes("secondary", true),
    do:
      "px-6 py-3 bg-gray-800 text-white font-medium rounded-lg cursor-not-allowed transform transition-all duration-200 scale-100"

  defp button_classes("secondary", false),
    do:
      "px-6 py-3 bg-gray-700 text-white font-medium rounded-lg hover:bg-gray-600 transform transition-all duration-200 hover:scale-105"

  defp button_classes(_, _), do: ""

  @doc """
  Renders a form input with modern styling.
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :value, :string, default: ""
  attr :placeholder, :string, default: ""
  attr :maxlength, :integer, default: nil
  attr :show_count, :boolean, default: false
  attr :rest, :global, include: ~w(autocomplete phx-keyup phx-change)

  def form_input(assigns) do
    ~H"""
    <div>
      <label for={@id} class="block text-sm font-medium text-gray-300 mb-2">
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={@value}
        placeholder={@placeholder}
        maxlength={@maxlength}
        class="w-full px-4 py-3 bg-gray-900/50 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent transition-all duration-200"
        {@rest}
      />
      <%= if @show_count && @maxlength do %>
        <div class="mt-1 text-right">
          <span class="text-xs text-gray-400">{String.length(@value)}/{@maxlength}</span>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a form select with modern styling.
  """
  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :options, :list, required: true
  attr :rest, :global, include: ~w(phx-change)

  def form_select(assigns) do
    ~H"""
    <div>
      <label for={@id} class="block text-sm font-medium text-gray-300 mb-2">
        {@label}
      </label>
      <div class="relative">
        <select
          name={@name}
          id={@id}
          class="w-full px-4 py-3 bg-gray-900/50 border border-gray-600 rounded-lg text-white appearance-none cursor-pointer focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent transition-all duration-200"
          {@rest}
        >
          <%= for option <- @options do %>
            <option value={option} selected={option == @value}>
              {option |> String.capitalize() |> String.replace("_", " ")}
            </option>
          <% end %>
        </select>
        <div class="absolute inset-y-0 right-0 flex items-center px-2 pointer-events-none">
          <.icon name="hero-chevron-down" class="w-5 h-5 text-gray-400" />
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders an ASCII art display box.
  """
  attr :art, :string, required: true
  attr :copied, :boolean, default: false

  def ascii_display(assigns) do
    ~H"""
    <div class="animate-fadeIn">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-semibold text-gray-300">Generated ASCII Art</h3>
        <button
          id="copy-ascii"
          phx-click="copy_to_clipboard"
          phx-hook="CopyToClipboard"
          data-text={@art}
          class={[
            "px-4 py-2 text-sm font-medium rounded-lg transition-all duration-200",
            (@copied && "bg-green-600 text-white") || "bg-gray-700 text-gray-300 hover:bg-gray-600"
          ]}
        >
          <%= if @copied do %>
            <.icon name="hero-check" class="w-4 h-4 inline-block mr-1" /> Copied!
          <% else %>
            <.icon name="hero-clipboard-document" class="w-4 h-4 inline-block mr-1" /> Copy
          <% end %>
        </button>
      </div>
      <div class="bg-gray-900 rounded-xl p-6 overflow-x-auto">
        <pre class="font-mono text-sm text-green-400 whitespace-pre leading-relaxed"><%= @art %></pre>
      </div>
    </div>
    """
  end

  @doc """
  Renders a history item card.
  """
  attr :art, :map, required: true
  attr :on_click, :string, required: true

  def history_item(assigns) do
    ~H"""
    <div class="flex gap-2">
      <button
        phx-click={@on_click}
        phx-value-id={@art.id}
        class="flex-1 text-left p-4 bg-gray-900/50 rounded-lg border border-gray-700 hover:border-purple-500 transition-all duration-200 group"
      >
        <div class="font-medium text-gray-300 truncate group-hover:text-purple-400 transition-colors">
          {@art.text}
        </div>
        <div class="text-xs text-gray-500 mt-1 flex items-center justify-between">
          <span class="flex items-center">
            <.icon name="hero-paint-brush" class="w-3 h-3 mr-1" />
            {String.capitalize(@art.font)}
          </span>
          <span>{format_time_ago(@art.inserted_at)}</span>
        </div>
      </button>
      <button
        phx-click="delete_art"
        phx-value-id={@art.id}
        data-confirm="Are you sure you want to delete this art?"
        class="px-3 py-2 bg-red-600/20 text-red-400 rounded-lg hover:bg-red-600/30 transition-all duration-200"
      >
        <.icon name="hero-trash" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  @doc """
  Renders a stat item.
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :type, :string, default: "number"

  def stat_item(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-gray-400 text-sm">{@label}</span>
      <%= if @type == "number" do %>
        <span class="text-2xl font-bold text-purple-400">{@value}</span>
      <% else %>
        <span class="text-gray-300">{@value}</span>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a progress bar.
  """
  attr :value, :integer, required: true
  attr :max, :integer, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true

  def progress_bar(assigns) do
    percentage = round(assigns.value / assigns.max * 100)
    assigns = assign(assigns, :percentage, percentage)

    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-gray-300 text-sm capitalize">{String.replace(@label, "_", " ")}</span>
      <div class="flex items-center">
        <div class="w-24 bg-gray-700 rounded-full h-2 mr-2">
          <div
            class="bg-gradient-to-r from-purple-500 to-pink-500 h-2 rounded-full transition-all duration-500"
            style={"width: #{@percentage}%"}
          >
          </div>
        </div>
        <span class="text-gray-400 text-xs">{@count}</span>
      </div>
    </div>
    """
  end

  # Helper functions

  defp format_time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      diff < 60 -> "Just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> "#{div(diff, 604_800)}w ago"
    end
  end
end
