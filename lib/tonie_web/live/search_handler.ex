defmodule TonieWeb.SearchHandler do
  @moduledoc """
  Handles async search, artist browsing, and album duration fetching.
  Delegated to from YoutubeUploaderLive for handle_info callbacks.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2]
  alias Tonie.YTMusic

  def handle_search({:do_search, query}, socket) do
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

    if query == socket.assigns.search_query do
      socket = assign(socket, search_results: albums, artist_results: artists, searching: false)

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

  def handle_browse_artist({:do_browse_artist, artist_id}, socket) do
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

  def handle_fetch_duration({:fetch_album_duration, album_id}, socket) do
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

  def handle_restore_album({:restore_album, album_id}, socket) do
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

  # --- Private helpers ---

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
