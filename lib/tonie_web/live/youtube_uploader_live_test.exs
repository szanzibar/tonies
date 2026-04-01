defmodule TonieWeb.YoutubeUploaderLiveTest do
  use ExUnit.Case, async: true

  alias TonieWeb.YoutubeUploaderLive

  describe "youtube_url?/1" do
    test "recognizes youtube.com URLs" do
      assert YoutubeUploaderLive.youtube_url?("https://www.youtube.com/watch?v=abc123")
      assert YoutubeUploaderLive.youtube_url?("https://youtube.com/watch?v=abc123")
      assert YoutubeUploaderLive.youtube_url?("https://music.youtube.com/playlist?list=OLAK5uy_test")
      assert YoutubeUploaderLive.youtube_url?("http://youtube.com/watch?v=abc123")
    end

    test "recognizes youtu.be short URLs" do
      assert YoutubeUploaderLive.youtube_url?("https://youtu.be/abc123")
    end

    test "rejects non-YouTube URLs" do
      refute YoutubeUploaderLive.youtube_url?("https://example.com/audio.mp3")
      refute YoutubeUploaderLive.youtube_url?("https://cdn.podcast.com/episode.mp3")
      refute YoutubeUploaderLive.youtube_url?("https://notyoutube.com/watch?v=abc")
    end

    test "rejects garbage input" do
      refute YoutubeUploaderLive.youtube_url?("not a url")
      refute YoutubeUploaderLive.youtube_url?("")
    end
  end
end
