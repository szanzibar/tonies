defmodule Tonie.PodcastTest do
  use ExUnit.Case, async: true

  alias Tonie.Podcast

  describe "sanitize_for_filename/1" do
    test "passes through plain ASCII titles unchanged" do
      assert Podcast.sanitize_for_filename("Percy and the Calliope") ==
               "Percy and the Calliope"
    end

    test "strips trademark symbol and ampersand from the failing title" do
      # The actual episode title that triggered the Non-unicode filename warning:
      # "Percy and the Calliope - Thomas & Friends™ 80th Anniversary Storytime"
      # podcast_name and episode_title are sanitized separately before joining,
      # so test both parts individually.
      assert Podcast.sanitize_for_filename("Thomas Friends 80th Anniversary Storytime") ==
               "Thomas Friends 80th Anniversary Storytime"

      assert Podcast.sanitize_for_filename("Percy and the Calliope - Thomas & Friends™ 80th Anniversary Storytime") ==
               "Percy and the Calliope - Thomas  Friends 80th Anniversary Storytime"

      assert Podcast.sanitize_for_filename("Percy and the Calliope") ==
               "Percy and the Calliope"
    end

    test "strips curly apostrophe (U+2019) from valid UTF-8" do
      # U+2019 RIGHT SINGLE QUOTATION MARK — common in podcast titles
      assert Podcast.sanitize_for_filename("Thomas Friends\u2019 Storytime US") ==
               "Thomas Friends Storytime US"
    end

    test "produces valid UTF-8 output when input contains invalid UTF-8 bytes" do
      # Simulate what happens when a Latin-1 / Windows-1252 encoded RSS feed
      # sends \xe2 (the first byte of the UTF-8 sequence for U+2019) without its
      # continuation bytes — this was the root cause of the logged warning.
      invalid_utf8 = "Thomas Friends" <> <<0xE2>> <> " Storytime US"
      refute String.valid?(invalid_utf8)

      result = Podcast.sanitize_for_filename(invalid_utf8)

      assert String.valid?(result)
      assert result == "Thomas Friends Storytime US"
    end

    test "strips all high bytes when the entire input is invalid UTF-8" do
      # A Windows-1252 string with the right-single-quote encoded as \x92
      latin1_title = "Thomas Friends" <> <<0x92>> <> " Storytime"
      refute String.valid?(latin1_title)

      result = Podcast.sanitize_for_filename(latin1_title)

      assert String.valid?(result)
      assert result == "Thomas Friends Storytime"
    end

    test "trims surrounding whitespace" do
      assert Podcast.sanitize_for_filename("  Hello  ") == "Hello"
    end

    test "keeps hyphens, underscores, and dots" do
      assert Podcast.sanitize_for_filename("episode-01_final.mp3") == "episode-01_final.mp3"
    end

    test "strips characters unsafe for filenames: slashes, colons, null bytes" do
      result = Podcast.sanitize_for_filename("My Show: Episode 1/2")
      assert String.valid?(result)
      assert result == "My Show Episode 12"
    end
  end
end
