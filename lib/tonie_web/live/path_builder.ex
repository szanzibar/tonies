defmodule TonieWeb.PathBuilder do
  @moduledoc """
  Builds URL paths from socket assigns. Single source of truth for URL structure.
  """

  def build_path(socket, overrides) do
    tonie = Keyword.get(overrides, :tonie, socket.assigns.selected_tonie_id)
    view = Keyword.get(overrides, :view, :keep)

    current_view =
      cond do
        view != :keep -> view
        socket.assigns[:selected_album] -> "album"
        socket.assigns[:selected_episode] -> "episode"
        socket.assigns[:browsing_artist] -> "artist"
        socket.assigns[:browsing_podcast] -> "podcast"
        true -> nil
      end

    query = socket.assigns.search_query

    artist_id =
      case socket.assigns[:browsing_artist] do
        %{artist_id: id} when is_binary(id) -> id
        _ -> nil
      end

    {album_id, playlist_id} =
      case socket.assigns[:selected_album] do
        %{album_id: aid, playlist_id: pid} -> {aid, pid}
        _ -> {nil, nil}
      end

    {podcast_id, feed_url} =
      case socket.assigns[:browsing_podcast] do
        %{podcast_id: pid, feed_url: furl} when is_binary(furl) -> {pid, furl}
        _ -> {nil, nil}
      end

    episode_url =
      case socket.assigns[:selected_episode] do
        %{audio_url: url} when is_binary(url) -> url
        _ -> nil
      end

    params =
      %{}
      |> put_if("tonie", tonie)
      |> put_if("view", current_view)
      |> put_if("q", if(query not in ["", nil], do: query))
      |> put_if("artist_id", if(artist_id && current_view in ["artist", "album"], do: artist_id))
      |> put_if("album_id", if(album_id && current_view == "album", do: album_id))
      |> put_if("playlist_id", if(playlist_id && current_view == "album", do: playlist_id))
      |> put_if("podcast_id", if(podcast_id && current_view in ["podcast", "episode"], do: podcast_id))
      |> put_if("feed_url", if(feed_url && current_view in ["podcast", "episode"], do: feed_url))
      |> put_if("episode_url", if(episode_url && current_view == "episode", do: episode_url))

    case URI.encode_query(params) do
      "" -> "/"
      qs -> "/?" <> qs
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
