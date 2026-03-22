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
      # Saved artists (loaded from localStorage via hook)
      |> assign(:saved_artists, [])
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
      # Album duration (fetched on toggle)
      |> assign(:album_duration, nil)
      |> assign(:loading_duration, false)
      |> assign(:show_tracks, false)
      # Chapter editing state
      |> assign(:selected_chapter_indices, MapSet.new())
      |> assign(:range_start, nil)
      |> assign(:working_chapters, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket = assign(socket, :selected_tonie_id, params["tonie"])

    case params["view"] do
      "artist" ->
        handle_artist_params(params, socket)

      "album" ->
        handle_album_params(params, socket)

      _ ->
        handle_search_params(params, socket)
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
      # No artist data in assigns or URL — can't show this view
      socket.assigns.browsing_artist == nil and artist_id == nil ->
        {:noreply, push_patch(socket, to: "/", replace: true)}

      # Need to restore artist from URL params (e.g. after reconnect)
      socket.assigns.browsing_artist == nil and artist_id != nil ->
        socket =
          assign(socket,
            browsing_artist: %{name: nil, artist_id: artist_id, thumbnail: nil, subscribers: nil},
            loading_artist: true,
            artist_albums: []
          )

        send(self(), {:do_browse_artist, artist_id})
        {:noreply, socket}

      # Artist exists but albums missing (e.g. back from album after restore)
      socket.assigns.artist_albums == [] and not socket.assigns.loading_artist ->
        aid =
          socket.assigns.browsing_artist[:artist_id] || socket.assigns.browsing_artist.artist_id

        send(self(), {:do_browse_artist, aid})
        {:noreply, assign(socket, loading_artist: true)}

      # Normal case — data already in assigns
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
      # No album data in assigns or URL — can't show this view
      socket.assigns.selected_album == nil and (album_id == nil or playlist_id == nil) ->
        {:noreply, push_patch(socket, to: "/", replace: true)}

      # Need to restore album from URL params (e.g. after reconnect)
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

        # Restore browsing artist placeholder for back navigation
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

      # Normal case — data already in assigns from select_album event
      true ->
        {:noreply, socket}
    end
  end

  defp handle_search_params(params, socket) do
    search_query = params["q"] || socket.assigns.search_query || ""
    socket = assign(socket, search_query: search_query)

    if socket.assigns.browsing_artist do
      # Navigated back from artist view — clear artist state, keep cached search results
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

      # Restore search if we have a query but no results (e.g. after reconnect)
      if byte_size(search_query) >= 2 and socket.assigns.search_results == [] and
           socket.assigns.artist_results == [] and not socket.assigns.searching do
        send(self(), {:do_search, search_query})
        {:noreply, assign(socket, searching: true)}
      else
        {:noreply, socket}
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

    socket =
      assign(socket,
        browsing_artist: artist,
        loading_artist: true
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

    # Fetch duration info eagerly (song count + total length), but don't show track list
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
    # Go back to the previous view (artist or search)
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

  # --- Existing events ---

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

  # --- Chapter editing events ---

  @impl true
  def handle_event("toggle_chapter", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    case socket.assigns.range_start do
      nil ->
        selected = socket.assigns.selected_chapter_indices

        selected =
          if MapSet.member?(selected, index),
            do: MapSet.delete(selected, index),
            else: MapSet.put(selected, index)

        {:noreply, assign(socket, selected_chapter_indices: selected)}

      range_start when is_integer(range_start) ->
        {lo, hi} = Enum.min_max([range_start, index])
        new_indices = MapSet.new(lo..hi)
        selected = MapSet.union(socket.assigns.selected_chapter_indices, new_indices)
        {:noreply, assign(socket, selected_chapter_indices: selected, range_start: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("long_press_chapter", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    selected = MapSet.put(socket.assigns.selected_chapter_indices, index)
    {:noreply, assign(socket, range_start: index, selected_chapter_indices: selected)}
  end

  @impl true
  def handle_event("select_all_chapters", _params, socket) do
    {chapters, _selected} = current_chapters_and_selection(socket)
    count = length(chapters)

    {:noreply,
     assign(socket, selected_chapter_indices: MapSet.new(0..(count - 1)), range_start: nil)}
  end

  @impl true
  def handle_event("clear_chapter_selection", _params, socket) do
    {:noreply, assign(socket, selected_chapter_indices: MapSet.new(), range_start: nil)}
  end

  @impl true
  def handle_event("move_chapters_up", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, new_selected} = move_selection(chapters, selected, :up)

    {:noreply,
     assign(socket, working_chapters: new_chapters, selected_chapter_indices: new_selected)}
  end

  @impl true
  def handle_event("move_chapters_down", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, new_selected} = move_selection(chapters, selected, :down)

    {:noreply,
     assign(socket, working_chapters: new_chapters, selected_chapter_indices: new_selected)}
  end

  @impl true
  def handle_event("move_chapters_top", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, _new_selected} = move_to_edge(chapters, selected, :top)

    {:noreply,
     assign(socket,
       working_chapters: new_chapters,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

  @impl true
  def handle_event("move_chapters_bottom", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, _new_selected} = move_to_edge(chapters, selected, :bottom)

    {:noreply,
     assign(socket,
       working_chapters: new_chapters,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

  @impl true
  def handle_event("save_chapter_order", _params, socket) do
    tonie = selected_tonie(socket.assigns.tonies, socket.assigns.selected_tonie_id)

    send(self(), {:do_save_chapters, tonie, socket.assigns.working_chapters})

    {:noreply,
     assign(socket,
       selected_chapter_indices: MapSet.new(),
       range_start: nil,
       working_chapters: nil,
       status: :uploading,
       message: "Kapitel werden aktualisiert..."
     )}
  end

  @impl true
  def handle_event("discard_chapter_changes", _params, socket) do
    {:noreply,
     assign(socket,
       working_chapters: nil,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

  @impl true
  def handle_event("remove_selected_chapters", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)

    remaining_chapters =
      chapters
      |> Enum.with_index()
      |> Enum.reject(fn {_ch, i} -> MapSet.member?(selected, i) end)
      |> Enum.map(fn {ch, _i} -> ch end)

    {:noreply,
     assign(socket,
       working_chapters: remaining_chapters,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

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
    artist =
      Enum.find(socket.assigns.saved_artists, &(&1["artist_id"] == artist_id))

    if artist do
      browsing = %{
        name: artist["name"],
        artist_id: artist["artist_id"],
        thumbnail: artist["thumbnail"],
        subscribers: nil
      }

      socket =
        assign(socket,
          browsing_artist: browsing,
          loading_artist: true,
          artist_albums: []
        )

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
      socket = assign(socket, search_results: albums, artist_results: artists, searching: false)

      # Sync search query to URL (replace, no history entry) — only on search view
      # Skip push_patch when results are empty to avoid retriggering handle_params → do_search loop
      has_results = albums != [] or artists != []

      if has_results and socket.assigns.browsing_artist == nil and
           socket.assigns.selected_album == nil do
        {:noreply, push_patch(socket, to: build_path(socket, view: nil), replace: true)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:do_browse_artist, artist_id}, socket) do
    case socket.assigns.ytmusic_client do
      nil ->
        {:noreply, assign(socket, loading_artist: false)}

      client ->
        case YTMusic.browse_artist(client, artist_id) do
          {:ok, %{albums_browse_id: bid, albums_params: params} = info}
          when is_binary(bid) and is_binary(params) ->
            socket = merge_browsing_artist_info(socket, info)

            albums =
              case YTMusic.browse_artist_albums(client, bid, params) do
                {:ok, albums} -> albums
                _ -> []
              end

            {:noreply, assign(socket, artist_albums: albums, loading_artist: false)}

          {:ok, %{albums: albums} = info} ->
            socket = merge_browsing_artist_info(socket, info)
            {:noreply, assign(socket, artist_albums: albums, loading_artist: false)}

          _ ->
            {:noreply, assign(socket, loading_artist: false)}
        end
    end
  end

  @impl true
  def handle_info({:fetch_album_duration, album_id}, socket) do
    case socket.assigns.ytmusic_client do
      nil ->
        {:noreply, assign(socket, loading_duration: false)}

      client ->
        case YTMusic.get_album_page(client, album_id) do
          {:ok, info} ->
            if socket.assigns.selected_album &&
                 socket.assigns.selected_album.album_id == album_id do
              duration = %{
                songs: info[:songs],
                duration_text: info[:duration_text],
                tracks: info[:tracks] || []
              }

              {:noreply, assign(socket, album_duration: duration, loading_duration: false)}
            else
              {:noreply, socket}
            end

          _ ->
            {:noreply, assign(socket, loading_duration: false)}
        end
    end
  end

  @impl true
  def handle_info({:restore_album, album_id}, socket) do
    case socket.assigns.ytmusic_client do
      nil ->
        {:noreply, assign(socket, loading_duration: false)}

      client ->
        case YTMusic.get_album_page(client, album_id) do
          {:ok, info} ->
            current = socket.assigns.selected_album

            if current && current.album_id == album_id do
              updated_album = %{
                current
                | name: info[:name] || current.name,
                  thumbnail: info[:thumbnail] || current.thumbnail,
                  artist: info[:artist] || current[:artist],
                  year: info[:year] || current[:year]
              }

              duration = %{
                songs: info[:songs],
                duration_text: info[:duration_text],
                tracks: info[:tracks] || []
              }

              {:noreply,
               assign(socket,
                 selected_album: updated_album,
                 album_duration: duration,
                 loading_duration: false
               )}
            else
              {:noreply, socket}
            end

          _ ->
            {:noreply, assign(socket, loading_duration: false)}
        end
    end
  end

  @impl true
  def handle_info({msg, tonie, chapters}, socket)
      when msg in [:do_remove_chapters, :do_save_chapters] do
    token = Api.auth()
    household_id = Api.get_household(token)

    case Api.update_chapters(token, household_id, tonie, chapters) do
      :ok ->
        api_state = Api.init()

        {:noreply,
         assign(socket,
           tonies: api_state.tonies,
           working_chapters: nil,
           status: :idle,
           message:
             "Kapitel erfolgreich aktualisiert. Ohr 3 Sekunden halten zum Synchronisieren.",
           progress: 100
         )}

      _ ->
        {:noreply,
         assign(socket,
           status: :error,
           message: "Fehler beim Aktualisieren der Kapitel."
         )}
    end
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

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="main"
      phx-hook="SavedArtists"
      class="w-full max-w-4xl mx-auto p-3 sm:p-6 bg-white rounded-lg shadow-md"
    >
      <%!-- Nav bar: home + saved artist pills --%>
      <div class="mb-4 flex flex-wrap items-center gap-1.5">
        <button
          type="button"
          phx-click="go_home"
          class="flex items-center justify-center w-7 h-7 rounded-full bg-gray-100 hover:bg-gray-200 text-sm"
        >
          🏠
        </button>
        <%= for artist <- Enum.sort_by(@saved_artists, & &1["name"]) do %>
          <div class="group flex items-center gap-1 pl-1 pr-1.5 py-0.5 bg-gray-100 rounded-full text-xs hover:bg-gray-200 transition-colors">
            <img
              :if={artist["thumbnail"]}
              src={thumb(artist["thumbnail"])}
              class="w-5 h-5 rounded-full object-cover"
            />
            <button
              type="button"
              phx-click="select_saved_artist"
              phx-value-artist_id={artist["artist_id"]}
              class="text-gray-700 hover:text-gray-900 max-w-[8rem] truncate"
            >
              {artist["name"]}
            </button>
            <button
              type="button"
              phx-click="remove_saved_artist"
              phx-value-artist_id={artist["artist_id"]}
              class="text-gray-300 hover:text-red-400 ml-0.5"
            >
              ✕
            </button>
          </div>
        <% end %>
      </div>

      <.form for={%{}} phx-submit="submit" class="space-y-4 sm:space-y-6">
        <%!-- Step 1: Search or selected album --%>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Album suchen</label>

          <%= if @selected_album do %>
            <%!-- Selected album detail view --%>
            <div class="mb-2 flex items-center gap-3">
              <button
                type="button"
                phx-click="back_from_album"
                class="text-xs text-blue-600 hover:text-blue-800"
                disabled={@status != :idle}
              >
                ← Zurück
              </button>
              <button
                type="button"
                phx-click="clear_album"
                class="text-xs text-gray-400 hover:text-gray-600"
                disabled={@status != :idle}
              >
                Neue Suche
              </button>
            </div>

            <div class="bg-blue-50 border-2 border-blue-300 rounded-lg overflow-hidden">
              <%!-- Album header — tap to toggle track list --%>
              <div
                class="flex gap-4 p-4 cursor-pointer active:bg-blue-100 transition-colors"
                phx-click="toggle_tracks"
              >
                <div class="w-32 h-32 sm:w-40 sm:h-40 rounded-lg overflow-hidden bg-gray-100 flex-shrink-0 shadow-md">
                  <img
                    :if={@selected_album.thumbnail}
                    src={thumb(@selected_album.thumbnail)}
                    class="w-full h-full object-cover"
                  />
                </div>
                <div class="flex flex-col justify-center min-w-0">
                  <p class="font-semibold text-base sm:text-lg leading-tight">
                    {@selected_album.name}
                  </p>
                  <p class="text-sm text-gray-500 mt-1">
                    {if @browsing_artist, do: @browsing_artist.name, else: @selected_album[:artist]}
                  </p>
                  <p :if={@selected_album.year} class="text-xs text-gray-400 mt-0.5">
                    {@selected_album.year}
                  </p>
                  <%= if @loading_duration do %>
                    <p class="text-xs text-gray-400 animate-pulse mt-2">Wird geladen...</p>
                  <% else %>
                    <p :if={@album_duration} class="text-xs text-gray-400 mt-2">
                      {@album_duration.songs} · {@album_duration.duration_text}
                    </p>
                  <% end %>
                  <p class="text-xs text-blue-400 mt-1">
                    {if @show_tracks, do: "▾", else: "▸"} Tracklist
                  </p>
                </div>
              </div>

              <%!-- Track list — shown on toggle --%>
              <%= if @show_tracks do %>
                <%= if @loading_duration do %>
                  <div class="border-t border-blue-200 px-4 py-3 flex justify-center">
                    <div class="w-4 h-4 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
                  </div>
                <% else %>
                  <%= if @album_duration && @album_duration[:tracks] != [] do %>
                    <div class="border-t border-blue-200 px-4 py-3">
                      <ol class="space-y-1">
                        <%= for {track, i} <- Enum.with_index(@album_duration[:tracks] || []) do %>
                          <li class="flex items-baseline gap-2 text-sm">
                            <span class="text-xs text-gray-400 w-5 text-right flex-shrink-0">
                              {i + 1}
                            </span>
                            <span class="flex-1 truncate">{track.title}</span>
                            <span class="text-xs text-gray-400 flex-shrink-0">{track.duration}</span>
                          </li>
                        <% end %>
                      </ol>
                    </div>
                  <% end %>
                <% end %>
              <% end %>
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

              <% artist_saved =
                Enum.any?(
                  @saved_artists,
                  &(&1["artist_id"] == (@browsing_artist.artist_id || @browsing_artist[:artist_id]))
                ) %>
              <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-lg mb-3">
                <img
                  :if={@browsing_artist.thumbnail}
                  src={thumb(@browsing_artist.thumbnail)}
                  class="w-10 h-10 rounded-full object-cover flex-shrink-0"
                />
                <div class="flex-1 min-w-0">
                  <p class="font-medium text-sm">{@browsing_artist.name}</p>
                  <p class="text-xs text-gray-400">{@browsing_artist.subscribers}</p>
                </div>
                <button
                  :if={!artist_saved && @browsing_artist.name}
                  type="button"
                  phx-click="save_artist"
                  class="text-gray-300 hover:text-yellow-500 text-lg flex-shrink-0"
                  title="Merken"
                >
                  ☆
                </button>
                <span :if={artist_saved} class="text-yellow-400 text-lg flex-shrink-0">
                  ★
                </span>
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
                          src={thumb(album.thumbnail)}
                          class="w-full h-full object-cover"
                          loading="lazy"
                        />
                      </div>
                      <p class="mt-1 text-xs font-medium leading-tight line-clamp-2">{album.name}</p>
                      <p class="text-[10px] text-gray-400">{album.year}</p>
                    </button>
                  <% end %>
                </div>

                <p :if={@artist_albums == []} class="text-xs text-gray-400 text-center py-4">
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
                  placeholder="z.B. Paw Patrol, Globi, Schwiizergoofe..."
                  phx-debounce="400"
                  disabled={@status != :idle}
                />
                <div :if={@searching} class="absolute right-3 top-1/2 -translate-y-1/2">
                  <div class="w-4 h-4 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
                </div>
              </div>

              <%!-- Artist results (top) --%>
              <div :if={@artist_results != [] && !@searching} class="mt-3">
                <%= for {artist, index} <- Enum.with_index(Enum.take(@artist_results, 3)) do %>
                  <button
                    type="button"
                    phx-click="select_artist"
                    phx-value-index={index}
                    class="w-full flex items-center gap-3 p-2.5 hover:bg-gray-50 rounded-lg text-left transition-colors border border-gray-200 mb-1.5"
                  >
                    <img
                      :if={artist.thumbnail}
                      src={thumb(artist.thumbnail)}
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
              <div :if={@search_results != [] && !@searching} class="mt-3">
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
                          src={thumb(album.thumbnail)}
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
                :if={
                  @search_query != "" && @search_results == [] && @artist_results == [] && !@searching
                }
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
            <% chapters = @working_chapters || tonie["chapter_data"] %>
            <% has_selection = MapSet.size(@selected_chapter_indices) > 0 %>
            <div class="border-2 border-blue-500 ring-2 ring-blue-200 rounded-lg p-3 sm:p-4">
              <div class="flex items-start space-x-3 sm:space-x-4">
                <%!-- Left column: tonie image + sticky move buttons --%>
                <div class="flex-shrink-0 sticky top-3 self-start">
                  <img
                    src={tonie["imageUrl"]}
                    alt="Tonie"
                    class="w-16 h-16 sm:w-24 sm:h-24 rounded object-cover"
                  />
                  <% btn_enabled = "text-gray-600 bg-gray-100 hover:bg-gray-200 active:bg-gray-300" %>
                  <% btn_disabled = "text-gray-300 bg-gray-50 cursor-default" %>
                  <%= if has_selection || @working_chapters != nil do %>
                    <div class="flex flex-col items-center gap-1.5 mt-2 w-16 sm:w-24">
                      <%!-- Move --%>
                      <button
                        type="button"
                        phx-click="move_chapters_top"
                        disabled={!has_selection}
                        class={"w-full h-10 flex items-center justify-center rounded text-sm #{if has_selection, do: btn_enabled, else: btn_disabled}"}
                      >
                        ⤒
                      </button>
                      <button
                        type="button"
                        phx-click="move_chapters_up"
                        disabled={!has_selection}
                        class={"w-full h-10 flex items-center justify-center rounded text-sm #{if has_selection, do: btn_enabled, else: btn_disabled}"}
                      >
                        ↑
                      </button>
                      <button
                        type="button"
                        phx-click="move_chapters_down"
                        disabled={!has_selection}
                        class={"w-full h-10 flex items-center justify-center rounded text-sm #{if has_selection, do: btn_enabled, else: btn_disabled}"}
                      >
                        ↓
                      </button>
                      <button
                        type="button"
                        phx-click="move_chapters_bottom"
                        disabled={!has_selection}
                        class={"w-full h-10 flex items-center justify-center rounded text-sm #{if has_selection, do: btn_enabled, else: btn_disabled}"}
                      >
                        ⤓
                      </button>

                      <div class="w-full border-t border-gray-200 my-1"></div>

                      <%!-- Select / deselect --%>
                      <button
                        type="button"
                        phx-click="select_all_chapters"
                        class={"w-full h-10 flex items-center justify-center rounded text-xs #{btn_enabled}"}
                      >
                        Alle
                      </button>
                      <button
                        type="button"
                        phx-click="clear_chapter_selection"
                        disabled={!has_selection}
                        class={"w-full h-10 flex items-center justify-center rounded text-xs #{if has_selection, do: btn_enabled, else: btn_disabled}"}
                      >
                        Keine
                      </button>

                      <div class="w-full border-t border-gray-200 my-1"></div>

                      <%!-- Delete --%>
                      <button
                        type="button"
                        phx-click="remove_selected_chapters"
                        disabled={!has_selection}
                        class={"w-full h-10 flex items-center justify-center rounded #{if has_selection, do: "text-red-400 bg-red-50 hover:bg-red-100 active:bg-red-200", else: "text-red-200 bg-red-50/50 cursor-default"}"}
                      >
                        🗑
                      </button>

                      <%!-- Save/discard --%>
                      <%= if @working_chapters != nil do %>
                        <div class="w-full border-t border-gray-200 my-1"></div>
                        <button
                          type="button"
                          phx-click="save_chapter_order"
                          class="w-full h-10 flex items-center justify-center text-white bg-blue-600 rounded hover:bg-blue-700 active:bg-blue-800 text-sm font-medium"
                        >
                          ✓
                        </button>
                        <button
                          type="button"
                          phx-click="discard_chapter_changes"
                          class="w-full h-10 flex items-center justify-center text-gray-400 bg-gray-100 rounded hover:bg-gray-200 text-xs"
                        >
                          ✕
                        </button>
                      <% end %>
                    </div>
                  <% else %>
                    <%= if not Enum.empty?(tonie["chapters"]) do %>
                      <p class="mt-2 text-[10px] text-gray-400 text-center w-16 sm:w-24 leading-tight">
                        Tippen zum Auswählen · Gedrückt halten für Bereich
                      </p>
                    <% end %>
                  <% end %>
                </div>

                <%!-- Right column: info + chapters --%>
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
                    <div class="mt-2">
                      <%!-- Range mode hint --%>
                      <p
                        :if={is_integer(@range_start)}
                        class="text-xs text-orange-600 mb-1 animate-pulse"
                      >
                        Tippe auf den letzten Track des Bereichs
                      </p>

                      <%!-- Chapter list --%>
                      <div class="space-y-0.5">
                        <%= for {chapter, i} <- Enum.with_index(chapters) do %>
                          <% selected = MapSet.member?(@selected_chapter_indices, i) %>
                          <% is_range_start = @range_start == i %>
                          <div
                            id={"chapter-#{i}"}
                            phx-hook="LongPress"
                            phx-click="toggle_chapter"
                            phx-value-index={i}
                            data-index={i}
                            class={"flex items-center gap-2 w-full text-left px-2 py-1.5 rounded text-sm transition-colors select-none cursor-pointer #{cond do
                              is_range_start -> "bg-orange-100 text-orange-700 ring-1 ring-orange-300"
                              selected -> "bg-red-50 text-red-700"
                              true -> "hover:bg-gray-50 text-gray-700"
                            end}"}
                          >
                            <span class="flex-1 truncate">{chapter["title"]}</span>
                            <span
                              :if={selected && !is_range_start}
                              class="text-red-300 text-xs flex-shrink-0"
                            >
                              ✕
                            </span>
                            <span :if={is_range_start} class="text-orange-400 text-xs flex-shrink-0">
                              ↕
                            </span>
                          </div>
                        <% end %>
                      </div>
                    </div>
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
          disabled={
            @status != :idle || @selected_tonie_id == nil ||
              (@selected_album == nil && @youtube_url == "" && !@show_url_input)
          }
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
            <div class="bg-blue-600 h-2.5 rounded-full transition-all" style={"width: #{@progress}%"}>
            </div>
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

  defp thumb(url) when is_binary(url) do
    "/thumb/" <> Base.url_encode64(url, padding: false)
  end

  defp thumb(_), do: nil

  defp current_chapters_and_selection(socket) do
    tonie = selected_tonie(socket.assigns.tonies, socket.assigns.selected_tonie_id)
    chapters = socket.assigns.working_chapters || tonie["chapter_data"]
    {chapters, socket.assigns.selected_chapter_indices}
  end

  defp move_selection(chapters, selected, direction) do
    sorted =
      selected
      |> MapSet.to_list()
      |> Enum.sort(if direction == :up, do: :asc, else: :desc)

    max_idx = length(chapters) - 1

    Enum.reduce(sorted, {chapters, MapSet.new()}, fn idx, {chs, new_sel} ->
      neighbor = if direction == :up, do: idx - 1, else: idx + 1

      if neighbor < 0 or neighbor > max_idx or MapSet.member?(new_sel, neighbor) do
        {chs, MapSet.put(new_sel, idx)}
      else
        item = Enum.at(chs, idx)
        other = Enum.at(chs, neighbor)

        new_chs =
          chs
          |> List.replace_at(idx, other)
          |> List.replace_at(neighbor, item)

        {new_chs, MapSet.put(new_sel, neighbor)}
      end
    end)
  end

  defp move_to_edge(chapters, selected, direction) do
    selected_sorted = selected |> MapSet.to_list() |> Enum.sort()
    selected_items = Enum.map(selected_sorted, &Enum.at(chapters, &1))

    remaining =
      chapters
      |> Enum.with_index()
      |> Enum.reject(fn {_ch, i} -> MapSet.member?(selected, i) end)
      |> Enum.map(fn {ch, _i} -> ch end)

    new_chapters =
      case direction do
        :top -> selected_items ++ remaining
        :bottom -> remaining ++ selected_items
      end

    count = length(selected_items)

    new_selected =
      case direction do
        :top -> MapSet.new(0..(count - 1))
        :bottom -> MapSet.new((length(chapters) - count)..(length(chapters) - 1))
      end

    {new_chapters, new_selected}
  end

  defp merge_browsing_artist_info(socket, artist_info) do
    case socket.assigns.browsing_artist do
      nil ->
        socket

      current ->
        updated = %{
          current
          | name: artist_info[:name] || current[:name],
            thumbnail: artist_info[:thumbnail] || current[:thumbnail]
        }

        assign(socket, :browsing_artist, updated)
    end
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
