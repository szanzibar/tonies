defmodule TonieWeb.YoutubeUploaderLive do
  use TonieWeb, :live_view
  alias Tonie.Worker
  alias Tonie.Api
  alias Tonie.YTMusic
  alias TonieWeb.ChapterEditor
  alias TonieWeb.SearchHandler

  import TonieWeb.YoutubeUploaderComponents

  @topic "youtube_worker"

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Tonie.PubSub, @topic)

    api_state = Api.init()
    status = Worker.get_status()

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
      |> assign(:saved_artists, [])
      |> assign(:ytmusic_client, ytmusic_client)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:artist_results, [])
      |> assign(:searching, false)
      |> assign(:selected_album, nil)
      |> assign(:show_url_input, false)
      |> assign(:browsing_artist, nil)
      |> assign(:artist_albums, [])
      |> assign(:loading_artist, false)
      |> assign(:album_duration, nil)
      |> assign(:loading_duration, false)
      |> assign(:show_tracks, false)
      |> assign(:selected_chapter_indices, MapSet.new())
      |> assign(:range_start, nil)
      |> assign(:working_chapters, nil)

    {:ok, socket}
  end

  # --- Routing ---

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, :selected_tonie_id, params["tonie"])

    case params["view"] do
      "artist" -> handle_artist_params(params, socket)
      "album" -> handle_album_params(params, socket)
      _ -> handle_search_params(params, socket)
    end
  end

  defp handle_artist_params(params, socket) do
    artist_id = params["artist_id"]
    search_query = params["q"] || socket.assigns.search_query || ""

    socket =
      assign(socket,
        search_query: search_query,
        selected_album: nil,
        youtube_url: "",
        album_duration: nil,
        loading_duration: false
      )

    cond do
      socket.assigns.browsing_artist == nil and artist_id == nil ->
        {:noreply, push_patch(socket, to: "/", replace: true)}

      socket.assigns.browsing_artist == nil and artist_id != nil ->
        socket =
          assign(socket,
            browsing_artist: %{name: nil, artist_id: artist_id, thumbnail: nil, subscribers: nil},
            loading_artist: true,
            artist_albums: []
          )

        send(self(), {:do_browse_artist, artist_id})
        {:noreply, socket}

      socket.assigns.artist_albums == [] and not socket.assigns.loading_artist ->
        aid =
          socket.assigns.browsing_artist[:artist_id] || socket.assigns.browsing_artist.artist_id

        send(self(), {:do_browse_artist, aid})
        {:noreply, assign(socket, loading_artist: true)}

      true ->
        {:noreply, socket}
    end
  end

  defp handle_album_params(params, socket) do
    album_id = params["album_id"]
    playlist_id = params["playlist_id"]
    artist_id = params["artist_id"]
    search_query = params["q"] || socket.assigns.search_query || ""

    socket = assign(socket, search_query: search_query)

    cond do
      socket.assigns.selected_album == nil and (album_id == nil or playlist_id == nil) ->
        {:noreply, push_patch(socket, to: "/", replace: true)}

      socket.assigns.selected_album == nil and album_id != nil and playlist_id != nil ->
        socket =
          assign(socket,
            selected_album: %{
              name: nil,
              album_id: album_id,
              playlist_id: playlist_id,
              thumbnail: nil,
              year: nil,
              artist: nil
            },
            youtube_url: YTMusic.playlist_url(playlist_id),
            album_duration: nil,
            loading_duration: true
          )

        socket =
          if artist_id && socket.assigns.browsing_artist == nil do
            assign(socket,
              browsing_artist: %{
                name: nil,
                artist_id: artist_id,
                thumbnail: nil,
                subscribers: nil
              }
            )
          else
            socket
          end

        send(self(), {:restore_album, album_id})
        {:noreply, socket}

      true ->
        {:noreply, socket}
    end
  end

  defp handle_search_params(params, socket) do
    search_query = params["q"] || socket.assigns.search_query || ""
    socket = assign(socket, search_query: search_query)

    if socket.assigns.browsing_artist do
      has_cached_results =
        socket.assigns.search_results != [] or socket.assigns.artist_results != []

      socket =
        assign(socket,
          browsing_artist: nil,
          artist_albums: [],
          loading_artist: false,
          selected_album: nil,
          youtube_url: "",
          album_duration: nil,
          loading_duration: false
        )

      if not has_cached_results and byte_size(search_query) >= 2 do
        send(self(), {:do_search, search_query})
        {:noreply, assign(socket, searching: true)}
      else
        {:noreply, socket}
      end
    else
      socket =
        assign(socket,
          selected_album: nil,
          youtube_url: "",
          album_duration: nil,
          loading_duration: false
        )

      if byte_size(search_query) >= 2 and socket.assigns.search_results == [] and
           socket.assigns.artist_results == [] and not socket.assigns.searching do
        send(self(), {:do_search, search_query})
        {:noreply, assign(socket, searching: true)}
      else
        {:noreply, socket}
      end
    end
  end

  # --- Search & browse events ---

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
    socket =
      assign(socket,
        search_query: query,
        searching: true,
        browsing_artist: nil,
        artist_albums: []
      )

    send(self(), {:do_search, query})
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_artist", %{"index" => index}, socket) do
    artist = Enum.at(socket.assigns.artist_results, String.to_integer(index))

    socket = assign(socket, browsing_artist: artist, loading_artist: true)

    send(self(), {:do_browse_artist, artist.artist_id})
    {:noreply, push_patch(socket, to: build_path(socket, view: "artist"))}
  end

  @impl true
  def handle_event("back_to_search", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, view: nil))}
  end

  @impl true
  def handle_event("select_album", %{"index" => index}, socket) do
    album =
      if socket.assigns.browsing_artist do
        Enum.at(socket.assigns.artist_albums, String.to_integer(index))
      else
        Enum.at(socket.assigns.search_results, String.to_integer(index))
      end

    if album.album_id do
      send(self(), {:fetch_album_duration, album.album_id})
    end

    socket =
      assign(socket,
        selected_album: album,
        youtube_url: YTMusic.playlist_url(album.playlist_id),
        album_duration: nil,
        loading_duration: album.album_id != nil,
        show_tracks: false
      )

    {:noreply, push_patch(socket, to: build_path(socket, view: "album"))}
  end

  @impl true
  def handle_event("back_from_album", _params, socket) do
    view = if socket.assigns.browsing_artist, do: "artist", else: nil
    {:noreply, push_patch(socket, to: build_path(socket, view: view))}
  end

  @impl true
  def handle_event("toggle_tracks", _params, socket) do
    {:noreply, assign(socket, show_tracks: !socket.assigns.show_tracks)}
  end

  @impl true
  def handle_event("clear_album", _params, socket) do
    socket =
      assign(socket,
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

    {:noreply, push_patch(socket, to: build_path(socket, view: nil))}
  end

  @impl true
  def handle_event("go_home", _params, socket) do
    socket =
      assign(socket,
        selected_album: nil,
        youtube_url: "",
        search_query: "",
        search_results: [],
        artist_results: [],
        browsing_artist: nil,
        artist_albums: [],
        album_duration: nil,
        loading_duration: false,
        show_tracks: false,
        selected_tonie_id: nil,
        selected_chapter_indices: MapSet.new(),
        range_start: nil,
        working_chapters: nil
      )

    {:noreply, push_patch(socket, to: "/", replace: true)}
  end

  @impl true
  def handle_event("toggle_url_input", _params, socket) do
    {:noreply, assign(socket, :show_url_input, !socket.assigns.show_url_input)}
  end

  # --- Tonie selection ---

  @impl true
  def handle_event("select_tonie", %{"id" => tonie_id}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, tonie: tonie_id))}
  end

  @impl true
  def handle_event("deselect_tonie", _params, socket) do
    {:noreply,
     socket
     |> assign(selected_chapter_indices: MapSet.new(), range_start: nil, working_chapters: nil)
     |> push_patch(to: build_path(socket, tonie: nil))}
  end

  # --- Chapter editing (delegated) ---

  @impl true
  def handle_event(event, params, socket) when event in ~w(
    toggle_chapter long_press_chapter select_all_chapters clear_chapter_selection
    move_chapters_up move_chapters_down move_chapters_top move_chapters_bottom
    save_chapter_order discard_chapter_changes remove_selected_chapters
  ) do
    ChapterEditor.handle_event(event, params, socket)
  end

  # --- Upload ---

  @impl true
  def handle_event("set_upload_mode", %{"upload_mode" => upload_mode}, socket) do
    {:noreply, assign(socket, :upload_mode, upload_mode)}
  end

  @impl true
  def handle_event("save_artist", _params, socket) do
    artist = socket.assigns.browsing_artist

    if artist do
      entry = %{
        "name" => artist.name || artist[:name],
        "artist_id" => artist.artist_id || artist[:artist_id],
        "thumbnail" => artist.thumbnail || artist[:thumbnail]
      }

      saved =
        [entry | socket.assigns.saved_artists]
        |> Enum.uniq_by(& &1["artist_id"])

      {:noreply,
       socket
       |> assign(:saved_artists, saved)
       |> push_event("save_artists", %{artists: saved})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_saved_artist", %{"artist_id" => artist_id}, socket) do
    saved = Enum.reject(socket.assigns.saved_artists, &(&1["artist_id"] == artist_id))

    {:noreply,
     socket
     |> assign(:saved_artists, saved)
     |> push_event("save_artists", %{artists: saved})}
  end

  @impl true
  def handle_event("load_saved_artists", %{"artists" => artists}, socket) do
    {:noreply, assign(socket, :saved_artists, artists || [])}
  end

  @impl true
  def handle_event("select_saved_artist", %{"artist_id" => artist_id}, socket) do
    artist = Enum.find(socket.assigns.saved_artists, &(&1["artist_id"] == artist_id))

    if artist do
      browsing = %{
        name: artist["name"],
        artist_id: artist["artist_id"],
        thumbnail: artist["thumbnail"],
        subscribers: nil
      }

      socket = assign(socket, browsing_artist: browsing, loading_artist: true, artist_albums: [])

      send(self(), {:do_browse_artist, artist["artist_id"]})
      {:noreply, push_patch(socket, to: build_path(socket, view: "artist"))}
    else
      {:noreply, socket}
    end
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

  # --- Async handlers (delegated) ---

  @impl true
  def handle_info({:do_search, _query} = msg, socket) do
    SearchHandler.handle_search(msg, socket)
  end

  @impl true
  def handle_info({:do_browse_artist, _artist_id} = msg, socket) do
    SearchHandler.handle_browse_artist(msg, socket)
  end

  @impl true
  def handle_info({:fetch_album_duration, _album_id} = msg, socket) do
    SearchHandler.handle_fetch_duration(msg, socket)
  end

  @impl true
  def handle_info({:restore_album, _album_id} = msg, socket) do
    SearchHandler.handle_restore_album(msg, socket)
  end

  @impl true
  def handle_info({msg, _tonie, _chapters} = payload, socket)
      when msg in [:do_remove_chapters, :do_save_chapters] do
    ChapterEditor.handle_save_chapters(payload, socket)
  end

  @impl true
  def handle_info({:status_update, %{status: :idle, progress: 100} = status}, socket) do
    api_state = Api.init()

    socket =
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
      |> assign(:tonies, api_state.tonies)

    {:noreply, push_patch(socket, to: build_path(socket, view: nil), replace: true)}
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

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div id="main" phx-hook="SavedArtists" class="w-full max-w-4xl mx-auto p-3 sm:p-6 bg-white rounded-lg shadow-md">
      <.nav_bar saved_artists={@saved_artists} />

      <.form for={%{}} phx-submit="submit" class="space-y-4 sm:space-y-6">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Album suchen</label>

          <%= if @selected_album do %>
            <.album_detail {assigns} />
          <% else %>
            <%= if @browsing_artist do %>
              <.artist_browse {assigns} />
            <% else %>
              <.search_panel {assigns} />
            <% end %>
          <% end %>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">Tonie wählen</label>

          <%= if @selected_tonie_id do %>
            <.tonie_detail {assigns} />
          <% else %>
            <.tonie_selector tonies={@tonies} />
          <% end %>
        </div>

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
          disabled={
            @status != :idle || @selected_tonie_id == nil ||
              (@selected_album == nil && @youtube_url == "" && !@show_url_input)
          }
        >
          Start Upload
        </button>
      </.form>

      <.status_bar status={@status} progress={@progress} message={@message} />
    </div>
    """
  end

  # --- Path builder ---

  defp build_path(socket, overrides) do
    tonie = Keyword.get(overrides, :tonie, socket.assigns.selected_tonie_id)
    view = Keyword.get(overrides, :view, :keep)

    current_view =
      cond do
        view != :keep -> view
        socket.assigns.selected_album -> "album"
        socket.assigns.browsing_artist -> "artist"
        true -> nil
      end

    query = socket.assigns.search_query

    artist_id =
      case socket.assigns.browsing_artist do
        %{artist_id: id} when is_binary(id) -> id
        _ -> nil
      end

    {album_id, playlist_id} =
      case socket.assigns.selected_album do
        %{album_id: aid, playlist_id: pid} -> {aid, pid}
        _ -> {nil, nil}
      end

    params =
      %{}
      |> then(fn p -> if tonie, do: Map.put(p, "tonie", tonie), else: p end)
      |> then(fn p -> if current_view, do: Map.put(p, "view", current_view), else: p end)
      |> then(fn p -> if query != "" and query != nil, do: Map.put(p, "q", query), else: p end)
      |> then(fn p ->
        if artist_id && current_view in ["artist", "album"],
          do: Map.put(p, "artist_id", artist_id),
          else: p
      end)
      |> then(fn p ->
        if album_id && current_view == "album", do: Map.put(p, "album_id", album_id), else: p
      end)
      |> then(fn p ->
        if playlist_id && current_view == "album",
          do: Map.put(p, "playlist_id", playlist_id),
          else: p
      end)

    case URI.encode_query(params) do
      "" -> "/"
      qs -> "/?" <> qs
    end
  end
end
