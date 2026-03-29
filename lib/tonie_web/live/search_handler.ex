defmodule TonieWeb.SearchHandler do
  @moduledoc """
  Handles the unified async search across all content sources (YTMusic + Podcast).
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_patch: 2]
  import TonieWeb.PathBuilder

  alias Tonie.YTMusic

  def handle_search({:do_search, query}, socket) do
    podcast_task = Task.async(fn -> Tonie.Podcast.search(query) end)

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

    podcasts =
      case Task.await(podcast_task, 10_000) do
        {:ok, p} -> p
        _ -> []
      end

    if query == socket.assigns.search_query do
      socket =
        assign(socket,
          search_results: albums,
          artist_results: artists,
          podcast_results: podcasts,
          searching: false
        )

      has_results = albums != [] or artists != [] or podcasts != []

      if has_results and socket.assigns.browsing_artist == nil and
           socket.assigns.browsing_podcast == nil and
           socket.assigns.selected_album == nil do
        {:noreply, push_patch(socket, to: build_path(socket, view: nil), replace: true)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end
end
