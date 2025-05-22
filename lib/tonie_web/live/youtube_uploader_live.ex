defmodule TonieWeb.YoutubeUploaderLive do
  use TonieWeb, :live_view
  alias Tonie.Worker
  alias Tonie.Api

  @topic "youtube_worker"

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Tonie.PubSub, @topic)

    # Initialize API and get tonies
    api_state = Api.init()

    # Get current worker status
    status = Worker.get_status()

    socket =
      socket
      |> assign(:youtube_url, "")
      |> assign(:selected_tonie_id, nil)
      |> assign(:tonies, api_state.tonies)
      |> assign(:status, status.status)
      |> assign(:message, status.message)
      |> assign(:progress, status.progress)

    {:ok, socket}
  end

  @impl true
  def handle_event("submit", %{"youtube_url" => youtube_url, "tonie_id" => tonie_id}, socket) do
    case Worker.start_job(youtube_url, tonie_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Job started!")
         |> assign(:youtube_url, youtube_url)
         |> assign(:selected_tonie_id, tonie_id)}

      {:error, :busy} ->
        {:noreply,
         socket
         |> put_flash(:error, "Worker is busy. Please wait for the current job to complete.")}
    end
  end

  @impl true
  def handle_info({:status_update, status}, socket) do
    {:noreply,
     socket
     |> assign(:status, status.status)
     |> assign(:message, status.message)
     |> assign(:progress, status.progress)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto p-6 bg-white rounded-lg shadow-md">
      <h1 class="text-2xl font-bold mb-6">YouTube to Tonie Uploader</h1>

      <.form for={%{}} phx-submit="submit" class="space-y-6">
        <div>
          <label for="youtube_url" class="block text-sm font-medium text-gray-700">YouTube URL</label>
          <input
            type="text"
            id="youtube_url"
            name="youtube_url"
            value={@youtube_url}
            class="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm"
            placeholder="https://www.youtube.com/watch?v=..."
            required
            disabled={@status != :idle}
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Select Tonie</label>
          <div class="grid grid-cols-3 gap-3">
            <%= for tonie <- @tonies do %>
              <label class="relative cursor-pointer">
                <input
                  type="radio"
                  name="tonie_id"
                  value={tonie["id"]}
                  class="sr-only peer"
                  checked={@selected_tonie_id == tonie["id"]}
                  disabled={@status != :idle}
                />
                <div class="border-2 rounded-lg p-2 peer-checked:border-blue-500 peer-checked:ring-2 peer-checked:ring-blue-200 transition-all hover:bg-gray-50">
                  <img src={tonie["imageUrl"]} alt="Tonie" class="w-full h-auto rounded" />
                  <div class="mt-1 text-xs text-center truncate">
                    Tonie {String.slice(tonie["id"], 0, 8)}...
                  </div>
                </div>
              </label>
            <% end %>
          </div>
        </div>

        <button
          type="submit"
          class="w-full py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none"
          disabled={@status != :idle}
        >
          Start Upload
        </button>
      </.form>

      <div class="mt-8">
        <h2 class="text-lg font-semibold mb-2">Status</h2>
        <div class="p-4 border rounded-md">
          <div class="flex items-center justify-between mb-2">
            <span class={status_color(@status)}>{String.capitalize(to_string(@status))}</span>
            <span>{@progress}%</span>
          </div>

          <div class="w-full bg-gray-200 rounded-full h-2.5">
            <div class="bg-blue-600 h-2.5 rounded-full" style={"width: #{@progress}%"}></div>
          </div>

          <p class="mt-2 text-sm text-gray-600">{@message}</p>
        </div>
      </div>
    </div>
    """
  end

  defp status_color(status) do
    base = "font-medium"

    case status do
      :idle -> "#{base} text-gray-500"
      :downloading -> "#{base} text-blue-500"
      :uploading -> "#{base} text-purple-500"
      :completed -> "#{base} text-green-500"
      :error -> "#{base} text-red-500"
      _ -> "#{base} text-gray-500"
    end
  end
end
