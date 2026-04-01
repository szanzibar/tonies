defmodule TonieWeb.YoutubeUploaderLive do
  use TonieWeb, :live_view

  alias Tonie.Worker
  alias Tonie.Api
  alias Tonie.YTMusic
  alias TonieWeb.{ChapterEditor, MusicHandler, PodcastHandler, SearchHandler}

  import TonieWeb.YoutubeUploaderComponents
  import TonieWeb.MusicComponents
  import TonieWeb.PodcastComponents
  import TonieWeb.PathBuilder
  import TonieWeb.Translations

  @topic "youtube_worker"

  # --- Mount ---

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
      # General
      |> assign(:youtube_url, "")
      |> assign(:selected_tonie_id, nil)
      |> assign(:upload_mode, "replace")
      |> assign(:tonies, api_state.tonies)
      |> assign(:status, status.status)
      |> assign(:message, status.message)
      |> assign(:progress, status.progress)
      |> assign(:show_url_input, false)
      |> assign(:download_type, :yt_dlp)
      # Search
      |> assign(:ytmusic_client, ytmusic_client)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:artist_results, [])
      |> assign(:podcast_results, [])
      |> assign(:searching, false)
      # Music
      |> assign(:saved_artists, [])
      |> assign(:browsing_artist, nil)
      |> assign(:artist_albums, [])
      |> assign(:loading_artist, false)
      |> assign(:selected_album, nil)
      |> assign(:album_duration, nil)
      |> assign(:loading_duration, false)
      |> assign(:show_tracks, false)
      # Podcast
      |> assign(:saved_podcasts, [])
      |> assign(:browsing_podcast, nil)
      |> assign(:podcast_episodes, [])
      |> assign(:loading_podcast, false)
      |> assign(:selected_episode, nil)
      |> assign(:show_notes, false)
      # Chapter editor
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
      "artist" -> MusicHandler.handle_params(:artist, params, socket)
      "album" -> MusicHandler.handle_params(:album, params, socket)
      "podcast" -> PodcastHandler.handle_params(:browse, params, socket)
      "episode" -> PodcastHandler.handle_params(:episode, params, socket)
      _ -> handle_search_params(params, socket)
    end
  end

  defp handle_search_params(params, socket) do
    search_query = params["q"] || socket.assigns.search_query || ""
    socket = assign(socket, search_query: search_query)

    if socket.assigns.browsing_artist || socket.assigns.browsing_podcast do
      has_cached_results =
        socket.assigns.search_results != [] or socket.assigns.artist_results != [] or
          socket.assigns.podcast_results != []

      socket = socket |> reset_music_state() |> reset_podcast_state()

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
          selected_episode: nil,
          youtube_url: "",
          album_duration: nil,
          loading_duration: false,
          download_type: :yt_dlp
        )

      if byte_size(search_query) >= 2 and socket.assigns.search_results == [] and
           socket.assigns.artist_results == [] and socket.assigns.podcast_results == [] and
           not socket.assigns.searching do
        send(self(), {:do_search, search_query})
        {:noreply, assign(socket, searching: true)}
      else
        {:noreply, socket}
      end
    end
  end

  # --- Search events (shared across sources) ---

  @impl true
  def handle_event("search", %{"value" => query}, socket) when byte_size(query) < 2 do
    {:noreply,
     socket
     |> reset_music_state()
     |> reset_podcast_state()
     |> assign(
       search_query: query,
       search_results: [],
       artist_results: [],
       podcast_results: [],
       searching: false
     )}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    socket =
      socket
      |> reset_music_state()
      |> reset_podcast_state()
      |> assign(search_query: query, searching: true)

    send(self(), {:do_search, query})
    {:noreply, socket}
  end

  @impl true
  def handle_event("back_to_search", _params, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, view: nil))}
  end

  # --- Navigation resets ---

  @impl true
  def handle_event("clear_album", _params, socket) do
    {:noreply,
     socket
     |> reset_content_state()
     |> push_patch(to: build_path(socket, view: nil))}
  end

  @impl true
  def handle_event("clear_podcast", _params, socket) do
    {:noreply,
     socket
     |> reset_content_state()
     |> push_patch(to: build_path(socket, view: nil))}
  end

  @impl true
  def handle_event("go_home", _params, socket) do
    socket =
      socket
      |> reset_content_state()
      |> assign(
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

  # --- Delegated events ---

  @impl true
  def handle_event(event, params, socket) when event in ~w(
    select_artist select_album back_from_album toggle_tracks
    save_artist remove_saved_artist load_saved_artists select_saved_artist
  ) do
    MusicHandler.handle_event(event, params, socket)
  end

  @impl true
  def handle_event(event, params, socket) when event in ~w(
    select_podcast select_episode back_from_episode toggle_show_notes
    save_podcast remove_saved_podcast load_saved_podcasts select_saved_podcast
  ) do
    PodcastHandler.handle_event(event, params, socket)
  end

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
  def handle_event(
        "submit",
        %{"youtube_url" => url, "tonie_id" => tonie_id, "upload_mode" => upload_mode},
        socket
      ) do
    mode = String.to_existing_atom(upload_mode)

    download_opts =
      if socket.assigns.download_type == :direct do
        podcast_name = get_in(socket.assigns, [:browsing_podcast, :name])
        episode_title = get_in(socket.assigns, [:selected_episode, :title])

        %{
          download_fn: fn -> Tonie.Podcast.download_episode(url, podcast_name, episode_title) end,
          total_tracks: 1,
          message: t(:downloading)
        }
      else
        %{
          download_fn: fn -> Tonie.YtDlp.download(url) end,
          track_count_fn: fn -> Tonie.YtDlp.get_track_count(url) end,
          message: t(:downloading)
        }
      end

    case Worker.start_job(tonie_id, mode, download_opts) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, t(:job_started))
         |> assign(:youtube_url, url)
         |> assign(:selected_tonie_id, tonie_id)
         |> assign(:upload_mode, upload_mode)}

      {:error, :busy} ->
        {:noreply,
         socket
         |> put_flash(:error, t(:worker_busy))}
    end
  end

  # --- Async handlers (delegated) ---

  @impl true
  def handle_info({:do_search, _query} = msg, socket) do
    SearchHandler.handle_search(msg, socket)
  end

  @impl true
  def handle_info({tag, _} = msg, socket)
      when tag in [:do_browse_artist, :fetch_album_duration, :restore_album] do
    MusicHandler.handle_info(msg, socket)
  end

  @impl true
  def handle_info({:do_browse_podcast, _feed_url} = msg, socket) do
    PodcastHandler.handle_info(msg, socket)
  end

  @impl true
  def handle_info({:do_restore_episode, _feed_url, _episode_url} = msg, socket) do
    PodcastHandler.handle_info(msg, socket)
  end

  @impl true
  def handle_info({msg, _tonie, _chapters} = payload, socket)
      when msg in [:do_remove_chapters, :do_save_chapters] do
    ChapterEditor.handle_save_chapters(payload, socket)
  end

  # --- Status updates ---

  @impl true
  def handle_info({:status_update, %{status: :idle, progress: 100} = status}, socket) do
    api_state = Api.init()

    socket =
      socket
      |> assign(:status, status.status)
      |> assign(:message, status.message)
      |> assign(:progress, status.progress)
      |> assign(:tonies, api_state.tonies)
      |> reset_content_state()

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
      <.nav_bar saved_artists={@saved_artists} saved_podcasts={@saved_podcasts} />

      <.form for={%{}} phx-submit="submit" class="space-y-4 sm:space-y-6">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">{t(:search_label)}</label>

          <%= cond do %>
            <% @selected_album != nil -> %>
              <.album_detail {assigns} />
            <% @selected_episode != nil -> %>
              <.episode_detail {assigns} />
            <% @browsing_artist != nil -> %>
              <.artist_browse {assigns} />
            <% @browsing_podcast != nil -> %>
              <.podcast_browse {assigns} />
            <% true -> %>
              <.search_panel {assigns} />
          <% end %>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 mb-2">{t(:tonie_label)}</label>

          <%= if @selected_tonie_id do %>
            <.tonie_detail {assigns} />
          <% else %>
            <.tonie_selector tonies={@tonies} />
          <% end %>
        </div>

        <div>
          <label for="upload_mode" class="block text-sm font-medium text-gray-700 mb-1">
            {t(:mode_label)}
          </label>
          <select
            id="upload_mode"
            name="upload_mode"
            phx-hook="PersistUploadMode"
            class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm focus:ring-blue-500 focus:border-blue-500"
            disabled={@status != :idle}
          >
            <option value="prepend" selected={@upload_mode == "prepend"}>
              {t(:prepend)}
            </option>
            <option value="replace" selected={@upload_mode == "replace"}>
              {t(:replace)}
            </option>
            <option value="append" selected={@upload_mode == "append"}>
              {t(:append)}
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
          {t(:start_upload)}
        </button>
      </.form>

      <.status_bar status={@status} progress={@progress} message={@message} />
    </div>
    """
  end

  # --- State reset helpers ---

  defp reset_music_state(socket) do
    assign(socket,
      browsing_artist: nil,
      artist_albums: [],
      loading_artist: false,
      selected_album: nil,
      youtube_url: "",
      album_duration: nil,
      loading_duration: false,
      show_tracks: false
    )
  end

  defp reset_podcast_state(socket) do
    assign(socket,
      browsing_podcast: nil,
      podcast_episodes: [],
      loading_podcast: false,
      selected_episode: nil,
      show_notes: false,
      download_type: :yt_dlp
    )
  end

  defp reset_content_state(socket) do
    socket
    |> reset_music_state()
    |> reset_podcast_state()
    |> assign(
      search_query: "",
      search_results: [],
      artist_results: [],
      podcast_results: [],
      searching: false,
      youtube_url: ""
    )
  end
end
