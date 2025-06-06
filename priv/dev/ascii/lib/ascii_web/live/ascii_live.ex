defmodule AsciiWeb.AsciiLive do
  use AsciiWeb, :live_view
  alias Ascii.{ArtGenerator, ArtHistory}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:text, "")
     |> assign(:font, "standard")
     |> assign(:ascii_art, "")
     |> assign(:recent_arts, ArtHistory.list_recent(5))
     |> assign(:available_fonts, ArtGenerator.list_fonts())
     |> assign(:generating, false)
     |> assign(:copied, false)
     |> assign(:show_history, false)
     |> assign(:stats, ArtHistory.get_stats())}
  end

  @impl true
  def handle_event("update_text", %{"value" => value}, socket) do
    {:noreply, assign(socket, :text, value)}
  end

  @impl true
  def handle_event("change_font", %{"font" => font}, socket) do
    {:noreply, assign(socket, :font, font)}
  end

  @impl true
  def handle_event("generate", _params, socket) do
    text = socket.assigns.text
    font = socket.assigns.font

    if String.trim(text) != "" do
      socket = assign(socket, :generating, true)
      Process.send_after(self(), {:do_generate, text, font}, 300)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Please enter some text to transform")}
    end
  end

  @impl true
  def handle_event("load_from_history", %{"id" => id}, socket) do
    art = ArtHistory.get_art!(id)

    {:noreply,
     socket
     |> assign(:text, art.text)
     |> assign(:font, art.font)
     |> assign(:ascii_art, art.result)
     |> assign(:show_history, false)}
  end

  @impl true
  def handle_event("generate_banner", _params, socket) do
    text = socket.assigns.text

    if String.trim(text) != "" do
      banner = ArtGenerator.generate_banner(text, 80)

      {:noreply, assign(socket, :ascii_art, banner)}
    else
      {:noreply, put_flash(socket, :error, "Please enter some text for the banner")}
    end
  end

  @impl true
  def handle_event("copy_to_clipboard", _params, socket) do
    socket = assign(socket, :copied, true)
    Process.send_after(self(), :reset_copied, 2000)
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_history", _params, socket) do
    {:noreply, assign(socket, :show_history, !socket.assigns.show_history)}
  end

  @impl true
  def handle_event("delete_art", %{"id" => id}, socket) do
    case ArtHistory.delete_art(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:recent_arts, ArtHistory.list_recent(5))
         |> assign(:stats, ArtHistory.get_stats())
         |> put_flash(:info, "Art deleted successfully")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Art not found")}
    end
  end

  @impl true
  def handle_info({:do_generate, text, font}, socket) do
    case ArtGenerator.generate(text, font) do
      {:ok, art} ->
        {:ok, _} =
          ArtHistory.create_art(%{
            text: text,
            font: font,
            result: art
          })

        {:noreply,
         socket
         |> assign(:ascii_art, art)
         |> assign(:recent_arts, ArtHistory.list_recent(5))
         |> assign(:stats, ArtHistory.get_stats())
         |> assign(:generating, false)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Failed to generate ASCII art")
         |> assign(:generating, false)}
    end
  end

  @impl true
  def handle_info(:reset_copied, socket) do
    {:noreply, assign(socket, :copied, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-violet-900">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div class="text-center mb-12">
          <h1 class="text-6xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-purple-400 to-pink-600 mb-4">
            ASCII Art Studio
          </h1>
          <p class="text-xl text-gray-300">Transform your text into beautiful ASCII art</p>
        </div>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div class="lg:col-span-2 space-y-8">
            <.glass_panel>
              <form phx-submit="generate" class="space-y-6">
                <.form_input
                  id="text"
                  name="text"
                  label="Your Text"
                  value={@text}
                  placeholder="Enter your creative text..."
                  maxlength={100}
                  show_count={true}
                  phx-keyup="update_text"
                  autocomplete="off"
                />

                <.form_select
                  id="font"
                  name="font"
                  label="Font Style"
                  value={@font}
                  options={@available_fonts}
                  phx-change="change_font"
                />

                <div class="flex flex-col sm:flex-row gap-4">
                  <.gradient_button
                    type="submit"
                    variant="primary"
                    disabled={@generating || String.trim(@text) == ""}
                    class="flex-1"
                  >
                    <%= if @generating do %>
                      <span class="flex items-center justify-center">
                        <div class="animate-spin -ml-1 mr-3 h-5 w-5">
                          <.icon name="hero-arrow-path" class="w-5 h-5" />
                        </div>
                        Generating...
                      </span>
                    <% else %>
                      Generate ASCII Art
                    <% end %>
                  </.gradient_button>
                  <.gradient_button
                    type="button"
                    variant="secondary"
                    disabled={String.trim(@text) == ""}
                    phx-click="generate_banner"
                  >
                    <.icon name="hero-document-text" class="w-5 h-5 inline-block mr-2" /> Banner Style
                  </.gradient_button>
                </div>
              </form>
            </.glass_panel>

            <%= if @ascii_art != "" do %>
              <.glass_panel class="animate-fadeIn">
                <.ascii_display art={@ascii_art} copied={@copied} />
              </.glass_panel>
            <% end %>
          </div>

          <div class="space-y-6">
            <button
              phx-click="toggle_history"
              class="lg:hidden w-full px-4 py-3 bg-gray-800/50 backdrop-blur-md rounded-lg border border-gray-700 text-gray-300 font-medium flex items-center justify-center"
            >
              <.icon name="hero-clock" class="w-5 h-5 mr-2" />
              {if @show_history, do: "Hide", else: "Show"} History
            </button>

            <div class={["lg:block space-y-6", (@show_history && "block") || "hidden"]}>
              <.glass_panel>
                <h3 class="text-lg font-semibold text-gray-300 mb-4 flex items-center">
                  <.icon name="hero-clock" class="w-5 h-5 mr-2 text-purple-400" /> Recent Creations
                </h3>

                <%= if @recent_arts == [] do %>
                  <div class="text-center py-8">
                    <.icon name="hero-document" class="w-12 h-12 mx-auto text-gray-600 mb-3" />
                    <p class="text-gray-500 text-sm">No art generated yet</p>
                    <p class="text-gray-600 text-xs mt-1">Start creating!</p>
                  </div>
                <% else %>
                  <div class="space-y-3">
                    <%= for art <- @recent_arts do %>
                      <.history_item art={art} on_click="load_from_history" />
                    <% end %>
                  </div>
                <% end %>
              </.glass_panel>

              <.glass_panel>
                <h3 class="text-lg font-semibold text-gray-300 mb-4 flex items-center">
                  <.icon name="hero-chart-bar" class="w-5 h-5 mr-2 text-pink-400" /> Statistics
                </h3>
                <div class="space-y-4">
                  <.stat_item
                    label="Total Generations"
                    value={@stats.total_generations}
                    type="number"
                  />

                  <%= if map_size(@stats.font_usage) > 0 do %>
                    <div class="pt-2 border-t border-gray-700">
                      <p class="text-gray-400 text-sm mb-3">Font Usage</p>
                      <div class="space-y-2">
                        <%= for {font, count} <- @stats.font_usage do %>
                          <.progress_bar
                            label={font}
                            value={count}
                            max={@stats.total_generations}
                            count={count}
                          />
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </.glass_panel>
            </div>
          </div>
        </div>
      </div>
    </div>

    <style>
      @keyframes fadeIn {
        from { opacity: 0; transform: translateY(10px); }
        to { opacity: 1; transform: translateY(0); }
      }
      .animate-fadeIn {
        animation: fadeIn 0.5s ease-out;
      }
    </style>
    """
  end
end
