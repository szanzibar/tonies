defmodule TonieWeb.PathBuilderTest do
  use ExUnit.Case, async: true

  alias TonieWeb.PathBuilder

  # Build a minimal socket with the assigns PathBuilder reads.
  defp build_socket(overrides \\ %{}) do
    defaults = %{
      __changed__: %{},
      selected_tonie_id: nil,
      search_query: "",
      selected_album: nil,
      selected_episode: nil,
      browsing_artist: nil,
      browsing_podcast: nil
    }

    %Phoenix.LiveView.Socket{assigns: Map.merge(defaults, overrides)}
  end

  describe "build_path/2 base cases" do
    test "returns / with no state" do
      assert PathBuilder.build_path(build_socket(), []) == "/"
    end

    test "includes tonie param" do
      socket = build_socket(%{selected_tonie_id: "abc-123"})
      path = PathBuilder.build_path(socket, [])
      assert path =~ "tonie=abc-123"
    end

    test "includes search query" do
      socket = build_socket(%{search_query: "paw patrol"})
      path = PathBuilder.build_path(socket, [])
      assert path =~ "q=paw+patrol"
    end

    test "excludes empty search query" do
      socket = build_socket(%{search_query: ""})
      assert PathBuilder.build_path(socket, []) == "/"
    end
  end

  describe "build_path/2 overrides" do
    test "overrides tonie via keyword" do
      socket = build_socket(%{selected_tonie_id: "old"})
      path = PathBuilder.build_path(socket, tonie: "new")
      assert path =~ "tonie=new"
      refute path =~ "old"
    end

    test "clears tonie with nil override" do
      socket = build_socket(%{selected_tonie_id: "abc"})
      path = PathBuilder.build_path(socket, tonie: nil)
      refute path =~ "tonie"
    end

    test "overrides view to nil clears view-related params" do
      socket =
        build_socket(%{
          browsing_artist: %{artist_id: "UC123", name: "Test", thumbnail: nil, subscribers: nil}
        })

      path = PathBuilder.build_path(socket, view: nil)
      refute path =~ "view"
      refute path =~ "artist_id"
    end
  end

  describe "build_path/2 artist view" do
    test "includes view=artist and artist_id" do
      socket =
        build_socket(%{
          browsing_artist: %{artist_id: "UC123", name: "Test", thumbnail: nil, subscribers: nil},
          search_query: "test"
        })

      path = PathBuilder.build_path(socket, [])
      assert path =~ "view=artist"
      assert path =~ "artist_id=UC123"
      assert path =~ "q=test"
    end
  end

  describe "build_path/2 album view" do
    test "includes view=album with album_id and playlist_id" do
      socket =
        build_socket(%{
          browsing_artist: %{artist_id: "UC123", name: "Test", thumbnail: nil, subscribers: nil},
          selected_album: %{
            album_id: "MPREb_abc",
            playlist_id: "OLAK5uy_xyz",
            name: "Album",
            thumbnail: nil,
            year: "2024"
          },
          search_query: "test"
        })

      path = PathBuilder.build_path(socket, [])
      assert path =~ "view=album"
      assert path =~ "album_id=MPREb_abc"
      assert path =~ "playlist_id=OLAK5uy_xyz"
      assert path =~ "artist_id=UC123"
    end
  end

  describe "build_path/2 podcast view" do
    test "includes view=podcast with feed_url and podcast_id" do
      socket =
        build_socket(%{
          browsing_podcast: %{
            podcast_id: "123",
            feed_url: "https://example.com/feed.xml",
            name: "Pod",
            thumbnail: nil,
            author: nil
          }
        })

      path = PathBuilder.build_path(socket, [])
      assert path =~ "view=podcast"
      assert path =~ "podcast_id=123"
      assert path =~ URI.encode_www_form("https://example.com/feed.xml")
    end
  end

  describe "build_path/2 episode view" do
    test "includes view=episode with episode_url and podcast info" do
      socket =
        build_socket(%{
          browsing_podcast: %{
            podcast_id: "123",
            feed_url: "https://example.com/feed.xml",
            name: "Pod",
            thumbnail: nil,
            author: nil
          },
          selected_episode: %{
            audio_url: "https://example.com/ep1.mp3",
            title: "Ep 1"
          }
        })

      path = PathBuilder.build_path(socket, [])
      assert path =~ "view=episode"
      assert path =~ "podcast_id=123"
      assert path =~ URI.encode_www_form("https://example.com/ep1.mp3")
    end
  end

  describe "build_path/2 combines tonie with view" do
    test "tonie and album in the same path" do
      socket =
        build_socket(%{
          selected_tonie_id: "tonie-1",
          browsing_artist: %{artist_id: "UC123", name: "A", thumbnail: nil, subscribers: nil},
          selected_album: %{
            album_id: "MPREb_abc",
            playlist_id: "OLAK5uy_xyz",
            name: "Album",
            thumbnail: nil,
            year: "2024"
          }
        })

      path = PathBuilder.build_path(socket, [])
      assert path =~ "tonie=tonie-1"
      assert path =~ "view=album"
      assert path =~ "album_id=MPREb_abc"
    end
  end
end
