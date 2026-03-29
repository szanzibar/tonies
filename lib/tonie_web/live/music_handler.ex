defmodule TonieWeb.MusicHandler do
  @moduledoc """
  Handles all YouTube Music events and async operations:
  artist/album browsing, selection, favorites, and URL restoration.
  """

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2, push_event: 3]
  import TonieWeb.PathBuilder

  alias Tonie.YTMusic

  @events ~w(
    select_artist select_album back_from_album toggle_tracks
    save_artist remove_saved_artist load_saved_artists select_saved_artist
  )

  def event?(name), do: name in @events

  # --- URL restoration ---

  def handle_params(:artist, params, socket) do
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

  def handle_params(:album, params, socket) do
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

  # --- Events ---

  def handle_event("select_artist", %{"index" => index}, socket) do
    artist = Enum.at(socket.assigns.artist_results, String.to_integer(index))

    socket = assign(socket, browsing_artist: artist, loading_artist: true)

    send(self(), {:do_browse_artist, artist.artist_id})
    {:noreply, push_patch(socket, to: build_path(socket, view: "artist"))}
  end

  def handle_event("select_album", %{"index" => index}, socket) do
    album =
      if socket.assigns.browsing_artist do
        Enum.at(socket.assigns.artist_albums, String.to_integer(index))
      else
        Enum.at(socket.assigns.search_results, String.to_integer(index))
      end

    if album.album_id, do: send(self(), {:fetch_album_duration, album.album_id})

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

  def handle_event("back_from_album", _params, socket) do
    view = if socket.assigns.browsing_artist, do: "artist", else: nil
    {:noreply, push_patch(socket, to: build_path(socket, view: view))}
  end

  def handle_event("toggle_tracks", _params, socket) do
    {:noreply, assign(socket, show_tracks: !socket.assigns.show_tracks)}
  end

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

  def handle_event("remove_saved_artist", %{"artist_id" => artist_id}, socket) do
    saved = Enum.reject(socket.assigns.saved_artists, &(&1["artist_id"] == artist_id))

    {:noreply,
     socket
     |> assign(:saved_artists, saved)
     |> push_event("save_artists", %{artists: saved})}
  end

  def handle_event("load_saved_artists", %{"artists" => artists}, socket) do
    {:noreply, assign(socket, :saved_artists, artists || [])}
  end

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

  # --- Async handlers ---

  def handle_info({:do_browse_artist, artist_id}, socket) do
    case socket.assigns.ytmusic_client do
      nil ->
        {:noreply, assign(socket, loading_artist: false)}

      client ->
        case YTMusic.browse_artist(client, artist_id) do
          {:ok, %{albums_browse_id: bid, albums_params: params} = info}
          when is_binary(bid) and is_binary(params) ->
            socket = merge_artist_info(socket, info)

            albums =
              case YTMusic.browse_artist_albums(client, bid, params) do
                {:ok, albums} -> albums
                _ -> []
              end

            {:noreply, assign(socket, artist_albums: albums, loading_artist: false)}

          {:ok, %{albums: albums} = info} ->
            socket = merge_artist_info(socket, info)
            {:noreply, assign(socket, artist_albums: albums, loading_artist: false)}

          _ ->
            {:noreply, assign(socket, loading_artist: false)}
        end
    end
  end

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

  # --- Private ---

  defp merge_artist_info(socket, info) do
    case socket.assigns.browsing_artist do
      nil ->
        socket

      current ->
        updated = %{
          current
          | name: info[:name] || current[:name],
            thumbnail: info[:thumbnail] || current[:thumbnail]
        }

        assign(socket, :browsing_artist, updated)
    end
  end
end
