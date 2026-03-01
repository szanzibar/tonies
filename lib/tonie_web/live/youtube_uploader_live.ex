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
      |> assign(:upload_mode, "replace")
      |> assign(:tonies, api_state.tonies)
      |> assign(:status, status.status)
      |> assign(:message, status.message)
      |> assign(:progress, status.progress)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_tonie", %{"id" => tonie_id}, socket) do
    {:noreply, assign(socket, :selected_tonie_id, tonie_id)}
  end

  @impl true
  def handle_event("deselect_tonie", _params, socket) do
    {:noreply, assign(socket, :selected_tonie_id, nil)}
  end

  @impl true
  def handle_event("set_upload_mode", %{"upload_mode" => upload_mode}, socket) do
    {:noreply, assign(socket, :upload_mode, upload_mode)}
  end

  @impl true
  def handle_event(
        "submit",
        %{"youtube_url" => youtube_url, "tonie_id" => tonie_id, "upload_mode" => upload_mode},
        socket
      ) do
    mode = String.to_existing_atom(upload_mode)

    case Worker.start_job(youtube_url, tonie_id, mode) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Job started!")
         |> assign(:youtube_url, youtube_url)
         |> assign(:selected_tonie_id, tonie_id)
         |> assign(:upload_mode, upload_mode)}

      {:error, :busy} ->
        {:noreply,
         socket
         |> put_flash(:error, "Worker is busy. Please wait for the current job to complete.")}
    end
  end

  @impl true
  def handle_info({:status_update, %{status: :idle} = status}, socket) do
    # Refetch tonies when job completes to show updated track list
    api_state = Api.init()

    {:noreply,
     socket
     |> assign(:status, status.status)
     |> assign(:message, status.message)
     |> assign(:progress, status.progress)
     |> assign(:tonies, api_state.tonies)}
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
    <div class="w-full max-w-4xl mx-auto p-3 sm:p-6 bg-white rounded-lg shadow-md">
      <h1 class="text-xl sm:text-2xl font-bold mb-4 sm:mb-6">YouTube to Tonie Uploader</h1>

      <.form for={%{}} phx-submit="submit" class="space-y-4 sm:space-y-6">
        <div>
          <label for="youtube_url" class="block text-sm font-medium text-gray-700">YouTube URL</label>
          <input
            type="text"
            id="youtube_url"
            name="youtube_url"
            value={@youtube_url}
            autocomplete="off"
            class="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm"
            placeholder="https://www.youtube.com/watch?v=..."
            required
            disabled={@status != :idle}
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Select Tonie</label>

          <%= if @selected_tonie_id do %>
            <% tonie = selected_tonie(@tonies, @selected_tonie_id) %>
            <div class="border-2 border-blue-500 ring-2 ring-blue-200 rounded-lg p-3 sm:p-4">
              <div class="flex items-start space-x-3 sm:space-x-4">
                <img
                  src={tonie["imageUrl"]}
                  alt="Tonie"
                  class="w-16 h-16 sm:w-24 sm:h-24 rounded object-cover flex-shrink-0"
                />
                <div class="flex-1 min-w-0 w-full">
                  <div class="flex justify-between items-center mb-1">
                    <div class="flex-1">
                      <div class="flex justify-between text-xs text-gray-400 mb-0.5">
                        <span>{format_duration(tonie["secondsRemaining"])} remaining</span>
                      </div>
                      <div class="w-full bg-gray-200 rounded-full h-1.5">
                        <div
                          class="bg-blue-500 h-1.5 rounded-full"
                          style={"width: #{usage_percent(tonie)}%"}
                        >
                        </div>
                      </div>
                    </div>
                    <button
                      type="button"
                      phx-click="deselect_tonie"
                      class="ml-3 text-xs text-blue-600 hover:text-blue-800 flex-shrink-0"
                    >
                      Change
                    </button>
                  </div>
                  <input type="hidden" name="tonie_id" value={tonie["id"]} />
                  <%= if Enum.empty?(tonie["chapters"]) do %>
                    <p class="text-xs sm:text-sm text-gray-500 italic mt-2">No chapters</p>
                  <% else %>
                    <ul class="list-disc list-inside text-xs sm:text-sm text-gray-600 mt-2">
                      <%= for chapter <- tonie["chapters"] do %>
                        <li class="w-full truncate">{chapter}</li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
              <%= for tonie <- @tonies do %>
                <div
                  class="border-2 rounded-lg p-3 sm:p-4 cursor-pointer transition-all hover:bg-gray-50"
                  phx-click="select_tonie"
                  phx-value-id={tonie["id"]}
                >
                  <div class="flex items-start space-x-3 sm:space-x-4">
                    <img
                      src={tonie["imageUrl"]}
                      alt="Tonie"
                      class="w-16 h-16 sm:w-24 sm:h-24 rounded object-cover flex-shrink-0"
                    />
                    <div class="flex-1 min-w-0 w-full">
                      <div class="mb-1">
                        <div class="flex justify-between text-xs text-gray-400 mb-0.5">
                          <span>{format_duration(tonie["secondsRemaining"])} remaining</span>
                        </div>
                        <div class="w-full bg-gray-200 rounded-full h-1.5">
                          <div
                            class="bg-blue-500 h-1.5 rounded-full"
                            style={"width: #{usage_percent(tonie)}%"}
                          >
                          </div>
                        </div>
                      </div>
                      <%= if Enum.empty?(tonie["chapters"]) do %>
                        <p class="text-xs sm:text-sm text-gray-500 italic">No chapters</p>
                      <% else %>
                        <ul class="list-disc list-inside text-xs sm:text-sm text-gray-600">
                          <%= for chapter <- Enum.take(tonie["chapters"], 3) do %>
                            <li class="w-full truncate">{chapter}</li>
                          <% end %>
                          <%= if length(tonie["chapters"]) > 3 do %>
                            <li class="text-gray-500 italic">
                              + {length(tonie["chapters"]) - 3} more...
                            </li>
                          <% end %>
                        </ul>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div>
          <label for="upload_mode" class="block text-sm font-medium text-gray-700 mb-1">
            Upload Mode
          </label>
          <select
            id="upload_mode"
            name="upload_mode"
            phx-hook="PersistUploadMode"
            class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm focus:ring-blue-500 focus:border-blue-500"
            disabled={@status != :idle}
          >
            <option value="prepend" selected={@upload_mode == "prepend"}>
              Add to beginning
            </option>
            <option value="replace" selected={@upload_mode == "replace"}>
              Replace all content
            </option>
            <option value="append" selected={@upload_mode == "append"}>
              Add to end
            </option>
          </select>
        </div>

        <button
          type="submit"
          class="w-full py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none"
          disabled={@status != :idle}
        >
          Start Upload
        </button>
      </.form>

      <div class="mt-6 sm:mt-8">
        <h2 class="text-lg font-semibold mb-2">Status</h2>
        <div class="p-3 sm:p-4 border rounded-md">
          <div class="flex items-center justify-between mb-2">
            <span class={status_color(@status)}>{String.capitalize(to_string(@status))}</span>
            <span>{@progress}%</span>
          </div>

          <div class="w-full bg-gray-200 rounded-full h-2.5">
            <div class="bg-blue-600 h-2.5 rounded-full" style={"width: #{@progress}%"}></div>
          </div>

          <p class="mt-2 text-xs sm:text-sm text-gray-600 break-words">{@message}</p>
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

  defp format_duration(seconds) when is_number(seconds) do
    minutes = trunc(seconds / 60)
    "#{minutes} min"
  end

  defp format_duration(_), do: "0 min"

  defp usage_percent(tonie) do
    present = tonie["secondsPresent"] || 0
    remaining = tonie["secondsRemaining"] || 0
    total = present + remaining

    if total > 0, do: trunc(present / total * 100), else: 0
  end

  defp selected_tonie(tonies, tonie_id) do
    Enum.find(tonies, &(&1["id"] == tonie_id))
  end
end
