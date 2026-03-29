defmodule TonieWeb.PodcastHandler do
  @moduledoc """
  Handles all podcast events and async operations:
  podcast/episode browsing, selection, favorites, and URL restoration.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2, push_event: 3]
  import TonieWeb.PathBuilder

  @events ~w(
    select_podcast select_episode back_from_episode toggle_show_notes
    save_podcast remove_saved_podcast load_saved_podcasts select_saved_podcast
  )

  def event?(name), do: name in @events

  # --- URL restoration ---

  def handle_params(:episode, _params, %{assigns: %{selected_episode: ep}} = socket)
      when ep != nil do
    # Episode already loaded (e.g. user just selected a tonie) — no-op
    {:noreply, socket}
  end

  def handle_params(:episode, params, socket) do
    feed_url = params["feed_url"]
    episode_url = params["episode_url"]
    podcast_id = params["podcast_id"]
    search_query = params["q"] || socket.assigns.search_query || ""

    if feed_url == nil or episode_url == nil do
      {:noreply, push_patch(socket, to: "/", replace: true)}
    else
      podcast =
        socket.assigns.browsing_podcast ||
          %{
            podcast_id: podcast_id || "",
            name: nil,
            author: nil,
            thumbnail: nil,
            feed_url: feed_url,
            episode_count: nil
          }

      socket =
        assign(socket,
          search_query: search_query,
          browsing_podcast: podcast,
          loading_podcast: true,
          youtube_url: episode_url,
          download_type: :direct,
          show_notes: false
        )

      send(self(), {:do_restore_episode, feed_url, episode_url})
      {:noreply, socket}
    end
  end

  def handle_params(:browse, params, socket) do
    feed_url = params["feed_url"]
    podcast_id = params["podcast_id"]
    search_query = params["q"] || socket.assigns.search_query || ""

    socket =
      assign(socket,
        search_query: search_query,
        selected_album: nil,
        selected_episode: nil,
        youtube_url: "",
        album_duration: nil,
        loading_duration: false,
        download_type: :yt_dlp
      )

    cond do
      socket.assigns.browsing_podcast == nil and feed_url == nil ->
        {:noreply, push_patch(socket, to: "/", replace: true)}

      socket.assigns.browsing_podcast == nil and feed_url != nil ->
        podcast = %{
          podcast_id: podcast_id || "",
          name: nil,
          author: nil,
          thumbnail: nil,
          feed_url: feed_url,
          episode_count: nil
        }

        socket =
          assign(socket,
            browsing_podcast: podcast,
            loading_podcast: true,
            podcast_episodes: []
          )

        send(self(), {:do_browse_podcast, feed_url})
        {:noreply, socket}

      socket.assigns.podcast_episodes == [] and not socket.assigns.loading_podcast ->
        furl = socket.assigns.browsing_podcast.feed_url
        send(self(), {:do_browse_podcast, furl})
        {:noreply, assign(socket, loading_podcast: true)}

      true ->
        {:noreply, socket}
    end
  end

  # --- Events ---

  def handle_event("select_podcast", %{"index" => index}, socket) do
    podcast = Enum.at(socket.assigns.podcast_results, String.to_integer(index))

    socket =
      assign(socket,
        browsing_podcast: podcast,
        loading_podcast: true,
        podcast_episodes: [],
        selected_episode: nil
      )

    send(self(), {:do_browse_podcast, podcast.feed_url})
    {:noreply, push_patch(socket, to: build_path(socket, view: "podcast"))}
  end

  def handle_event("select_episode", %{"index" => index}, socket) do
    episode = Enum.at(socket.assigns.podcast_episodes, String.to_integer(index))

    socket =
      assign(socket,
        selected_episode: episode,
        youtube_url: episode.audio_url,
        download_type: :direct,
        show_notes: false
      )

    {:noreply, push_patch(socket, to: build_path(socket, view: "episode"))}
  end

  def handle_event("back_from_episode", _params, socket) do
    socket =
      assign(socket,
        selected_episode: nil,
        youtube_url: "",
        download_type: :yt_dlp,
        show_notes: false
      )

    {:noreply, push_patch(socket, to: build_path(socket, view: "podcast"))}
  end

  def handle_event("toggle_show_notes", _params, socket) do
    {:noreply, assign(socket, show_notes: !socket.assigns.show_notes)}
  end

  def handle_event("save_podcast", _params, socket) do
    podcast = socket.assigns.browsing_podcast

    if podcast do
      entry = %{
        "name" => podcast.name,
        "podcast_id" => podcast.podcast_id,
        "thumbnail" => podcast.thumbnail,
        "author" => podcast.author,
        "feed_url" => podcast.feed_url
      }

      saved =
        [entry | socket.assigns.saved_podcasts]
        |> Enum.uniq_by(& &1["podcast_id"])

      {:noreply,
       socket
       |> assign(:saved_podcasts, saved)
       |> push_event("save_podcasts", %{podcasts: saved})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_saved_podcast", %{"podcast_id" => podcast_id}, socket) do
    saved = Enum.reject(socket.assigns.saved_podcasts, &(&1["podcast_id"] == podcast_id))

    {:noreply,
     socket
     |> assign(:saved_podcasts, saved)
     |> push_event("save_podcasts", %{podcasts: saved})}
  end

  def handle_event("load_saved_podcasts", %{"podcasts" => podcasts}, socket) do
    {:noreply, assign(socket, :saved_podcasts, podcasts || [])}
  end

  def handle_event("select_saved_podcast", %{"podcast_id" => podcast_id}, socket) do
    podcast = Enum.find(socket.assigns.saved_podcasts, &(&1["podcast_id"] == podcast_id))

    if podcast do
      browsing = %{
        podcast_id: podcast["podcast_id"],
        name: podcast["name"],
        author: podcast["author"],
        thumbnail: podcast["thumbnail"],
        feed_url: podcast["feed_url"],
        episode_count: nil
      }

      socket =
        assign(socket,
          browsing_podcast: browsing,
          loading_podcast: true,
          podcast_episodes: [],
          selected_episode: nil
        )

      send(self(), {:do_browse_podcast, podcast["feed_url"]})
      {:noreply, push_patch(socket, to: build_path(socket, view: "podcast"))}
    else
      {:noreply, socket}
    end
  end

  # --- Async handlers ---

  def handle_info({:do_restore_episode, feed_url, episode_url}, socket) do
    case Tonie.Podcast.get_episodes(feed_url) do
      {:ok, %{title: title, author: author, thumbnail: thumbnail, episodes: episodes}} ->
        socket = merge_podcast_info(socket, title, author, thumbnail)
        episode = Enum.find(episodes, &(&1.audio_url == episode_url))

        socket =
          assign(socket,
            podcast_episodes: episodes,
            loading_podcast: false,
            selected_episode: episode,
            youtube_url: if(episode, do: episode.audio_url, else: ""),
            download_type: if(episode, do: :direct, else: :yt_dlp)
          )

        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, loading_podcast: false)}
    end
  end

  def handle_info({:do_browse_podcast, feed_url}, socket) do
    case Tonie.Podcast.get_episodes(feed_url) do
      {:ok, %{title: title, author: author, thumbnail: thumbnail, episodes: episodes}} ->
        socket = merge_podcast_info(socket, title, author, thumbnail)
        {:noreply, assign(socket, podcast_episodes: episodes, loading_podcast: false)}

      _ ->
        {:noreply, assign(socket, loading_podcast: false)}
    end
  end

  # --- Private ---

  defp merge_podcast_info(socket, title, author, thumbnail) do
    case socket.assigns.browsing_podcast do
      nil ->
        socket

      current ->
        updated = %{
          current
          | name: title || current[:name] || current.name,
            author: author || current[:author] || current.author,
            thumbnail: thumbnail || current[:thumbnail] || current.thumbnail
        }

        assign(socket, :browsing_podcast, updated)
    end
  end
end
