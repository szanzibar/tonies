defmodule TonieWeb.YoutubeUploaderLive do
  use TonieWeb, :live_view
  alias Tonie.Worker
  alias Tonie.Api
  alias Tonie.YTMusic

  @topic "youtube_worker"

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Tonie.PubSub, @topic)

    api_state = Api.init()
    status = Worker.get_status()

    # Initialize YTMusic client in background
    ytmusic_client =
      case YTMusic.new() do
        {:ok, client} -> client
        {:error, _} -> nil
      end

    socket =
      socket
      |> assign(:youtube_url, "")
      |> assign(:selected_tonie_id, nil)
      |> assign(:upload_mode, "replace")
      |> assign(:tonies, api_state.tonies)
      |> assign(:status, status.status)
      |> assign(:message, status.message)
      |> assign(:progress, status.progress)
      |> assign(:anleitung_open, false)
      # Search state
      |> assign(:ytmusic_client, ytmusic_client)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:artist_results, [])
      |> assign(:searching, false)
      |> assign(:selected_album, nil)
      |> assign(:show_url_input, false)
      # Artist browse state
      |> assign(:browsing_artist, nil)
      |> assign(:artist_albums, [])
      |> assign(:loading_artist, false)
      # Album duration (fetched on selection)
      |> assign(:album_duration, nil)
      |> assign(:loading_duration, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, :selected_tonie_id, params["tonie"])

    case params["view"] do
      "artist" ->
        # If we navigated back to artist view but have a selected album, clear it
        {:noreply, assign(socket, selected_album: nil, youtube_url: "", album_duration: nil, loading_duration: false)}

      "album" ->
        # Album view — data already in assigns from select_album event
        {:noreply, socket}

      _ ->
        # Search view — if we had an artist or album selected, clear back to search
        if socket.assigns.browsing_artist do
          socket = assign(socket, browsing_artist: nil, artist_albums: [], loading_artist: false,
                          selected_album: nil, youtube_url: "", album_duration: nil, loading_duration: false)
          if byte_size(socket.assigns.search_query) >= 2 do
            send(self(), {:do_search, socket.assigns.search_query})
            {:noreply, assign(socket, searching: true)}
          else
            {:noreply, socket}
          end
        else
          {:noreply, assign(socket, selected_album: nil, youtube_url: "", album_duration: nil, loading_duration: false)}
        end
    end
  end

  # --- Search events ---

  @impl true
  def handle_event("search", %{"value" => query}, socket) when byte_size(query) < 2 do
    {:noreply,
     assign(socket,
       search_query: query,
       search_results: [],
       artist_results: [],
       searching: false,
       browsing_artist: nil,
       artist_albums: []
     )}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    socket = assign(socket, search_query: query, searching: true, browsing_artist: nil, artist_albums: [])
    send(self(), {:do_search, query})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_artist", %{"index" => index}, socket) do
    artist = Enum.at(socket.assigns.artist_results, String.to_integer(index))

    socket =
      assign(socket,
        browsing_artist: artist,
        loading_artist: true,
        search_results: [],
        artist_results: []
      )

    send(self(), {:do_browse_artist, artist.artist_id})
    {:noreply, push_patch(socket, to: build_path(socket, view: "artist"))}
  end

  @impl true
  def handle_event("back_to_search", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, view: nil))}
  end

  @impl true
  def handle_event("select_album", %{"index" => index}, socket) do
    # Could be from search results or artist albums
    album =
      if socket.assigns.browsing_artist do
        Enum.at(socket.assigns.artist_albums, String.to_integer(index))
      else
        Enum.at(socket.assigns.search_results, String.to_integer(index))
      end

    # Fetch duration in background
    if album.album_id do
      send(self(), {:fetch_album_duration, album.album_id})
    end

    socket =
      assign(socket,
        selected_album: album,
        youtube_url: YTMusic.playlist_url(album.playlist_id),
        album_duration: nil,
        loading_duration: album.album_id != nil
      )

    {:noreply, push_patch(socket, to: build_path(socket, view: "album"))}
  end

  @impl true
  def handle_event("back_from_album", _params, socket) do
    # Go back to the previous view (artist or search)
    view = if socket.assigns.browsing_artist, do: "artist", else: nil
    {:noreply, push_patch(socket, to: build_path(socket, view: view))}
  end

  @impl true
  def handle_event("clear_album", _params, socket) do
    {:noreply,
     socket
     |> assign(
       selected_album: nil,
       youtube_url: "",
       search_query: "",
       search_results: [],
       artist_results: [],
       browsing_artist: nil,
       artist_albums: [],
       album_duration: nil,
       loading_duration: false
     )
     |> push_patch(to: build_path(socket, view: nil))}
  end

  @impl true
  def handle_event("toggle_url_input", _params, socket) do
    {:noreply, assign(socket, :show_url_input, !socket.assigns.show_url_input)}
  end

  # --- Existing events ---

  @impl true
  def handle_event("select_tonie", %{"id" => tonie_id}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, tonie: tonie_id))}
  end

  @impl true
  def handle_event("deselect_tonie", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, tonie: nil))}
  end

  @impl true
  def handle_event("set_upload_mode", %{"upload_mode" => upload_mode}, socket) do
    {:noreply, assign(socket, :upload_mode, upload_mode)}
  end

  @impl true
  def handle_event("toggle_anleitung", _params, socket) do
    {:noreply, assign(socket, :anleitung_open, !socket.assigns.anleitung_open)}
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

  # --- Async search handler ---

  @impl true
  def handle_info({:do_search, query}, socket) do
    {artists, albums} =
      case socket.assigns.ytmusic_client do
        nil ->
          {[], []}

        client ->
          artist_task = Task.async(fn -> YTMusic.search_artists(client, query) end)
          album_task = Task.async(fn -> YTMusic.search_albums(client, query) end)

          artists =
            case Task.await(artist_task, 10_000) do
              {:ok, a} -> a
              _ -> []
            end

          albums =
            case Task.await(album_task, 10_000) do
              {:ok, a} -> a
              _ -> []
            end

          {artists, albums}
      end

    # Only update if the query still matches (user may have typed more)
    if query == socket.assigns.search_query do
      {:noreply, assign(socket, search_results: albums, artist_results: artists, searching: false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:do_browse_artist, artist_id}, socket) do
    albums =
      case socket.assigns.ytmusic_client do
        nil ->
          []

        client ->
          case YTMusic.browse_artist(client, artist_id) do
            {:ok, %{albums_browse_id: bid, albums_params: params}} when is_binary(bid) and is_binary(params) ->
              case YTMusic.browse_artist_albums(client, bid, params) do
                {:ok, albums} -> albums
                _ -> []
              end

            {:ok, %{albums: albums}} ->
              albums

            _ ->
              []
          end
      end

    {:noreply, assign(socket, artist_albums: albums, loading_artist: false)}
  end

  @impl true
  def handle_info({:fetch_album_duration, album_id}, socket) do
    case socket.assigns.ytmusic_client do
      nil ->
        {:noreply, assign(socket, loading_duration: false)}

      client ->
        duration =
          case YTMusic.get_album_duration(client, album_id) do
            {:ok, info} -> info
            _ -> nil
          end

        # Only update if this album is still selected
        if socket.assigns.selected_album && socket.assigns.selected_album.album_id == album_id do
          {:noreply, assign(socket, album_duration: duration, loading_duration: false)}
        else
          {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_info({:status_update, %{status: :idle, progress: 100} = status}, socket) do
    api_state = Api.init()

    {:noreply,
     socket
     |> assign(:status, status.status)
     |> assign(:message, status.message)
     |> assign(:progress, status.progress)
     |> assign(:youtube_url, "")
     |> assign(:selected_album, nil)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:artist_results, [])
     |> assign(:browsing_artist, nil)
     |> assign(:artist_albums, [])
     |> assign(:album_duration, nil)
     |> assign(:loading_duration, false)
     |> assign(:tonies, api_state.tonies)}
  end

  @impl true
  def handle_info({:status_update, %{status: :idle} = status}, socket) do
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

  def handle_info(msg, state) do
    require Logger
    Logger.debug("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full max-w-4xl mx-auto p-3 sm:p-6 bg-white rounded-lg shadow-md">
      <%!-- Instructions --%>
      <div class="mb-4">
        <button
          type="button"
          phx-click="toggle_anleitung"
          class="cursor-pointer text-sm text-blue-600 hover:text-blue-800 select-none"
        >
          ❓ Anleitung
        </button>
        <ol
          :if={@anleitung_open}
          class="mt-1 text-xs text-gray-600 list-decimal list-inside space-y-1 bg-gray-50 rounded-md p-3"
        >
          <li>Suche nach einem Album oder Künstler (z.B. «Paw Patrol» oder «Globi»).</li>
          <li>Wähle das gewünschte Album aus den Ergebnissen.</li>
          <li>Wähle den Tonie, auf den das Album geladen werden soll.</li>
          <li>Klicke auf <strong>«Start Upload»</strong>.</li>
          <li>
            Nach dem Upload: <strong>Ohr der Toniebox 3 Sekunden gedrückt halten</strong>, um die Inhalte zu synchronisieren.
          </li>
        </ol>
      </div>

      <.form for={%{}} phx-submit="submit" class="space-y-4 sm:space-y-6">
        <%!-- Step 1: Search or selected album --%>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Album suchen</label>

          <%= if @selected_album do %>
            <%!-- Selected album card --%>
            <div class="mb-2">
              <button
                type="button"
                phx-click="back_from_album"
                class="text-xs text-blue-600 hover:text-blue-800"
                disabled={@status != :idle}
              >
                ← Zurück
              </button>
            </div>
            <div class="flex items-center gap-3 p-3 bg-blue-50 border-2 border-blue-300 rounded-lg">
              <img
                :if={@selected_album.thumbnail}
                src={@selected_album.thumbnail}
                class="w-14 h-14 rounded object-cover flex-shrink-0"
              />
              <div class="flex-1 min-w-0">
                <p class="font-medium text-sm truncate">{@selected_album.name}</p>
                <p class="text-xs text-gray-500 truncate">
                  {if @browsing_artist, do: @browsing_artist.name, else: @selected_album[:artist]} · {@selected_album.year}
                </p>
                <%= if @loading_duration do %>
                  <p class="text-xs text-gray-400 animate-pulse">Dauer wird geladen...</p>
                <% else %>
                  <p :if={@album_duration} class="text-xs text-gray-400">
                    {@album_duration.songs} · {@album_duration.duration_text}
                  </p>
                <% end %>
              </div>
              <button
                type="button"
                phx-click="clear_album"
                class="text-xs text-gray-400 hover:text-gray-600 flex-shrink-0"
                disabled={@status != :idle}
              >
                Neue Suche
              </button>
            </div>
            <input type="hidden" name="youtube_url" value={@youtube_url} />

          <% else %>
            <%= if @browsing_artist do %>
              <%!-- Artist browse view --%>
              <div class="mb-3">
                <button
                  type="button"
                  phx-click="back_to_search"
                  class="text-xs text-blue-600 hover:text-blue-800"
                  disabled={@status != :idle}
                >
                  ← Zurück zur Suche
                </button>
              </div>

              <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-lg mb-3">
                <img
                  :if={@browsing_artist.thumbnail}
                  src={@browsing_artist.thumbnail}
                  class="w-10 h-10 rounded-full object-cover flex-shrink-0"
                />
                <div>
                  <p class="font-medium text-sm">{@browsing_artist.name}</p>
                  <p class="text-xs text-gray-400">{@browsing_artist.subscribers}</p>
                </div>
              </div>

              <%= if @loading_artist do %>
                <div class="flex justify-center py-8">
                  <div class="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
                </div>
              <% else %>
                <div class="grid grid-cols-3 sm:grid-cols-4 gap-2 sm:gap-3 max-h-[28rem] overflow-y-auto">
                  <%= for {album, index} <- Enum.with_index(@artist_albums) do %>
                    <button
                      type="button"
                      phx-click="select_album"
                      phx-value-index={index}
                      class="group text-left transition-all hover:scale-[1.03] active:scale-100"
                    >
                      <div class="aspect-square rounded-lg overflow-hidden bg-gray-100 shadow-sm group-hover:shadow-md transition-shadow">
                        <img
                          :if={album.thumbnail}
                          src={album.thumbnail}
                          class="w-full h-full object-cover"
                          loading="lazy"
                        />
                      </div>
                      <p class="mt-1 text-xs font-medium leading-tight line-clamp-2">{album.name}</p>
                      <p class="text-[10px] text-gray-400">{album.year}</p>
                    </button>
                  <% end %>
                </div>

                <p
                  :if={@artist_albums == []}
                  class="text-xs text-gray-400 text-center py-4"
                >
                  Keine Alben gefunden
                </p>
              <% end %>

            <% else %>
              <%!-- Search input --%>
              <div class="relative">
                <input
                  type="text"
                  value={@search_query}
                  phx-keyup="search"
                  name="query"
                  autocomplete="off"
                  class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm focus:ring-blue-500 focus:border-blue-500"
                  placeholder="z.B. Paw Patrol, Globi, Bibi und Tina..."
                  phx-debounce="400"
                  disabled={@status != :idle}
                />
                <div
                  :if={@searching}
                  class="absolute right-3 top-1/2 -translate-y-1/2"
                >
                  <div class="w-4 h-4 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
                </div>
              </div>

              <%!-- Artist results (top) --%>
              <div
                :if={@artist_results != [] && !@searching}
                class="mt-3"
              >
                <%= for {artist, index} <- Enum.with_index(Enum.take(@artist_results, 3)) do %>
                  <button
                    type="button"
                    phx-click="select_artist"
                    phx-value-index={index}
                    class="w-full flex items-center gap-3 p-2.5 hover:bg-gray-50 rounded-lg text-left transition-colors border border-gray-200 mb-1.5"
                  >
                    <img
                      :if={artist.thumbnail}
                      src={artist.thumbnail}
                      class="w-10 h-10 rounded-full object-cover flex-shrink-0"
                    />
                    <div class="flex-1 min-w-0">
                      <p class="text-sm font-medium truncate">{artist.name}</p>
                      <p class="text-xs text-gray-400">{artist.subscribers}</p>
                    </div>
                    <span class="text-xs text-blue-500 flex-shrink-0">Alben →</span>
                  </button>
                <% end %>
              </div>

              <%!-- Album results (grid with big art) --%>
              <div
                :if={@search_results != [] && !@searching}
                class="mt-3"
              >
                <p class="text-xs text-gray-400 mb-2">Alben</p>
                <div class="grid grid-cols-3 sm:grid-cols-4 gap-2 sm:gap-3 max-h-[28rem] overflow-y-auto">
                  <%= for {album, index} <- Enum.with_index(@search_results) do %>
                    <button
                      type="button"
                      phx-click="select_album"
                      phx-value-index={index}
                      class="group text-left transition-all hover:scale-[1.03] active:scale-100"
                    >
                      <div class="aspect-square rounded-lg overflow-hidden bg-gray-100 shadow-sm group-hover:shadow-md transition-shadow">
                        <img
                          :if={album.thumbnail}
                          src={album.thumbnail}
                          class="w-full h-full object-cover"
                          loading="lazy"
                        />
                      </div>
                      <p class="mt-1 text-xs font-medium leading-tight line-clamp-2">{album.name}</p>
                      <p class="text-[10px] text-gray-400 truncate">
                        {album.artist} · {album.year}
                      </p>
                    </button>
                  <% end %>
                </div>
              </div>

              <p
                :if={@search_query != "" && @search_results == [] && @artist_results == [] && !@searching}
                class="mt-2 text-xs text-gray-400"
              >
                Keine Ergebnisse für «{@search_query}»
              </p>

              <%!-- URL fallback (collapsed) --%>
              <div class="mt-3">
                <button
                  type="button"
                  phx-click="toggle_url_input"
                  class="text-xs text-gray-400 hover:text-gray-600"
                >
                  {if @show_url_input, do: "▾", else: "▸"} URL direkt eingeben
                </button>
                <div :if={@show_url_input} class="mt-1">
                  <input
                    type="text"
                    name="youtube_url"
                    value={@youtube_url}
                    autocomplete="off"
                    class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm"
                    placeholder="https://music.youtube.com/playlist?list=..."
                    disabled={@status != :idle}
                  />
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <%!-- Step 2: Select Tonie --%>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Tonie wählen</label>

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
                      Ändern
                    </button>
                  </div>
                  <input type="hidden" name="tonie_id" value={tonie["id"]} />
                  <%= if Enum.empty?(tonie["chapters"]) do %>
                    <p class="text-xs sm:text-sm text-gray-500 italic mt-2">Keine Kapitel</p>
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
                        <p class="text-xs sm:text-sm text-gray-500 italic">Keine Kapitel</p>
                      <% else %>
                        <ul class="list-disc list-inside text-xs sm:text-sm text-gray-600">
                          <%= for chapter <- Enum.take(tonie["chapters"], 3) do %>
                            <li class="w-full truncate">{chapter}</li>
                          <% end %>
                          <%= if length(tonie["chapters"]) > 3 do %>
                            <li class="text-gray-500 italic">
                              + {length(tonie["chapters"]) - 3} mehr...
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

        <%!-- Step 3: Upload mode --%>
        <div>
          <label for="upload_mode" class="block text-sm font-medium text-gray-700 mb-1">
            Modus
          </label>
          <select
            id="upload_mode"
            name="upload_mode"
            phx-hook="PersistUploadMode"
            class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm focus:ring-blue-500 focus:border-blue-500"
            disabled={@status != :idle}
          >
            <option value="prepend" selected={@upload_mode == "prepend"}>
              Am Anfang hinzufügen
            </option>
            <option value="replace" selected={@upload_mode == "replace"}>
              Alles ersetzen
            </option>
            <option value="append" selected={@upload_mode == "append"}>
              Am Ende hinzufügen
            </option>
          </select>
        </div>

        <button
          type="submit"
          class="w-full py-2.5 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none disabled:opacity-50 disabled:cursor-not-allowed"
          disabled={@status != :idle || @selected_tonie_id == nil || (@selected_album == nil && @youtube_url == "" && !@show_url_input)}
        >
          Start Upload
        </button>
      </.form>

      <%!-- Status --%>
      <div :if={@status != :idle || @progress > 0} class="mt-6 sm:mt-8">
        <div class="p-3 sm:p-4 border rounded-md">
          <div class="flex items-center justify-between mb-2">
            <span class={status_color(@status)}>{status_label(@status)}</span>
            <span class="text-sm">{@progress}%</span>
          </div>

          <div class="w-full bg-gray-200 rounded-full h-2.5">
            <div class="bg-blue-600 h-2.5 rounded-full transition-all" style={"width: #{@progress}%"}></div>
          </div>

          <p
            :for={line <- String.split(@message, "\n")}
            class="mt-2 text-xs sm:text-sm text-gray-600 break-words"
          >
            {line}
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp status_color(status) do
    base = "font-medium text-sm"

    case status do
      :idle -> "#{base} text-gray-500"
      :downloading -> "#{base} text-blue-500"
      :uploading -> "#{base} text-purple-500"
      :completed -> "#{base} text-green-500"
      :error -> "#{base} text-red-500"
      _ -> "#{base} text-gray-500"
    end
  end

  defp status_label(:downloading), do: "Wird heruntergeladen..."
  defp status_label(:uploading), do: "Wird hochgeladen..."
  defp status_label(:completed), do: "Fertig!"
  defp status_label(:error), do: "Fehler"
  defp status_label(_), do: "Bereit"

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

  defp build_path(socket, overrides) do
    tonie = Keyword.get(overrides, :tonie, socket.assigns.selected_tonie_id)
    view = Keyword.get(overrides, :view, :keep)

    # Determine current view from assigns if not overridden
    current_view =
      cond do
        view != :keep -> view
        socket.assigns.selected_album -> "album"
        socket.assigns.browsing_artist -> "artist"
        true -> nil
      end

    params =
      %{}
      |> then(fn p -> if tonie, do: Map.put(p, "tonie", tonie), else: p end)
      |> then(fn p -> if current_view, do: Map.put(p, "view", current_view), else: p end)

    case URI.encode_query(params) do
      "" -> "/"
      qs -> "/?" <> qs
    end
  end
end
