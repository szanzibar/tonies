defmodule Tonie.Podcast.RssParserTest do
  use ExUnit.Case, async: true

  alias Tonie.Podcast.RssParser

  # -- Full parse --

  describe "parse/1" do
    test "extracts channel title, author, image, and episodes" do
      xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss>
      <channel>
        <title>My Great Podcast</title>
        <itunes:author>Jane Host</itunes:author>
        <itunes:image href="https://example.com/art.jpg" />
        <item>
          <title>Episode 1</title>
          <pubDate>Mon, 15 Jan 2024 10:00:00 +0000</pubDate>
          <itunes:duration>1845</itunes:duration>
          <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg" />
        </item>
        <item>
          <title>Episode 2</title>
          <pubDate>Mon, 22 Jan 2024 10:00:00 +0000</pubDate>
          <itunes:duration>32:15</itunes:duration>
          <enclosure url="https://example.com/ep2.mp3" type="audio/mpeg" />
        </item>
      </channel>
      </rss>
      """

      result = RssParser.parse(xml)
      assert result.title == "My Great Podcast"
      assert result.author == "Jane Host"
      assert result.thumbnail == "https://example.com/art.jpg"
      assert length(result.episodes) == 2

      [ep1, ep2] = result.episodes
      assert ep1.title == "Episode 1"
      assert ep1.pub_date == "15 Jan 2024"
      assert ep1.duration == "30:45"
      assert ep1.audio_url == "https://example.com/ep1.mp3"

      assert ep2.title == "Episode 2"
      assert ep2.duration == "32:15"
    end

    test "filters out items without audio enclosure" do
      xml = """
      <rss><channel>
        <title>Test</title>
        <item>
          <title>Has Audio</title>
          <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
        </item>
        <item>
          <title>No Audio</title>
        </item>
      </channel></rss>
      """

      result = RssParser.parse(xml)
      assert length(result.episodes) == 1
      assert hd(result.episodes).title == "Has Audio"
    end

    test "falls back to managingEditor when itunes:author is missing" do
      xml = """
      <rss><channel>
        <title>Test</title>
        <managingEditor>editor@example.com</managingEditor>
      </channel></rss>
      """

      result = RssParser.parse(xml)
      assert result.author == "editor@example.com"
    end

    test "handles CDATA-wrapped content" do
      xml = """
      <rss><channel>
        <title><![CDATA[My <Cool> Podcast]]></title>
        <item>
          <title><![CDATA[Episode: "First!"]]></title>
          <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
        </item>
      </channel></rss>
      """

      result = RssParser.parse(xml)
      assert result.title == "My <Cool> Podcast"
      assert hd(result.episodes).title == "Episode: \"First!\""
    end

    test "returns nil fields gracefully for minimal feed" do
      xml = """
      <rss><channel></channel></rss>
      """

      result = RssParser.parse(xml)
      assert result.title == nil
      assert result.author == nil
      assert result.thumbnail == nil
      assert result.episodes == []
    end
  end

  # -- Enclosure extraction --

  describe "parse_episodes/1 enclosure extraction" do
    test "extracts audio URL with url before type" do
      xml = """
      <item>
        <title>Ep</title>
        <enclosure url="https://cdn.example.com/file.mp3" length="123" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.audio_url == "https://cdn.example.com/file.mp3"
    end

    test "extracts audio URL with type before url" do
      xml = """
      <item>
        <title>Ep</title>
        <enclosure type="audio/mpeg" url="https://cdn.example.com/file.mp3" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.audio_url == "https://cdn.example.com/file.mp3"
    end

    test "falls back to any enclosure url when type is not audio" do
      xml = """
      <item>
        <title>Ep</title>
        <enclosure url="https://cdn.example.com/file.mp3" type="application/octet-stream" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.audio_url == "https://cdn.example.com/file.mp3"
    end

    test "decodes HTML entities in enclosure URLs" do
      xml = """
      <item>
        <title>Ep</title>
        <enclosure url="https://example.com/ep.mp3?a=1&amp;b=2" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.audio_url == "https://example.com/ep.mp3?a=1&b=2"
    end
  end

  # -- Channel image extraction --

  describe "parse/1 channel image extraction" do
    test "extracts itunes:image href attribute" do
      xml = """
      <rss><channel>
        <itunes:image href="https://example.com/art.jpg" />
      </channel></rss>
      """

      assert RssParser.parse(xml).thumbnail == "https://example.com/art.jpg"
    end

    test "extracts nested itunes:image > url" do
      xml = """
      <rss><channel>
        <itunes:image><url>https://example.com/art2.jpg</url></itunes:image>
      </channel></rss>
      """

      assert RssParser.parse(xml).thumbnail == "https://example.com/art2.jpg"
    end

    test "falls back to image > url" do
      xml = """
      <rss><channel>
        <image><url>https://example.com/art3.jpg</url><title>Art</title></image>
      </channel></rss>
      """

      assert RssParser.parse(xml).thumbnail == "https://example.com/art3.jpg"
    end

    test "returns nil when no image is present" do
      xml = "<rss><channel><title>Test</title></channel></rss>"
      assert RssParser.parse(xml).thumbnail == nil
    end
  end

  # -- Date formatting --

  describe "parse_episodes/1 date formatting" do
    test "formats RFC 2822 date to short form" do
      xml = """
      <item>
        <title>Ep</title>
        <pubDate>Mon, 15 Jan 2024 10:00:00 +0000</pubDate>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.pub_date == "15 Jan 2024"
    end

    test "handles single-digit day" do
      xml = """
      <item>
        <title>Ep</title>
        <pubDate>Wed, 3 Mar 2023 08:00:00 GMT</pubDate>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.pub_date == "3 Mar 2023"
    end

    test "returns original string when format is unrecognized" do
      xml = """
      <item>
        <title>Ep</title>
        <pubDate>2024-01-15</pubDate>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.pub_date == "2024-01-15"
    end

    test "returns nil when pubDate is missing" do
      xml = """
      <item>
        <title>Ep</title>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.pub_date == nil
    end
  end

  # -- Duration formatting --

  describe "parse_episodes/1 duration formatting" do
    test "converts seconds to minutes:seconds" do
      xml = """
      <item>
        <title>Ep</title>
        <itunes:duration>125</itunes:duration>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.duration == "2:05"
    end

    test "converts large seconds to hours:minutes:seconds" do
      xml = """
      <item>
        <title>Ep</title>
        <itunes:duration>3661</itunes:duration>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.duration == "1:01:01"
    end

    test "passes through HH:MM:SS format unchanged" do
      xml = """
      <item>
        <title>Ep</title>
        <itunes:duration>1:23:45</itunes:duration>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.duration == "1:23:45"
    end

    test "passes through MM:SS format unchanged" do
      xml = """
      <item>
        <title>Ep</title>
        <itunes:duration>23:45</itunes:duration>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.duration == "23:45"
    end

    test "returns nil when duration is missing" do
      xml = """
      <item>
        <title>Ep</title>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.duration == nil
    end

    test "returns nil for empty duration" do
      xml = """
      <item>
        <title>Ep</title>
        <itunes:duration>  </itunes:duration>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.duration == nil
    end
  end

  # -- Entity decoding --

  describe "parse_episodes/1 entity decoding" do
    test "decodes standard XML entities in titles" do
      xml = """
      <item>
        <title>Tom &amp; Jerry&apos;s &quot;Best&quot; Episode</title>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.title == "Tom & Jerry's \"Best\" Episode"
    end

    test "decodes numeric character references" do
      xml = """
      <item>
        <title>Price: &#36;9.99 &#8212; Sale!</title>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.title == "Price: $9.99 \u2014 Sale!"
    end

    test "decodes hex character references" do
      xml = """
      <item>
        <title>Star &#x2605; Rating</title>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.title == "Star \u2605 Rating"
    end
  end

  # -- Description extraction --

  describe "parse_episodes/1 description" do
    test "strips HTML tags from description" do
      xml = """
      <item>
        <title>Ep</title>
        <description><![CDATA[<p>Hello <b>world</b></p>]]></description>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.description == "Hello world"
    end

    test "falls back to itunes:summary" do
      xml = """
      <item>
        <title>Ep</title>
        <itunes:summary>A brief summary</itunes:summary>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.description == "A brief summary"
    end

    test "returns empty string when no description" do
      xml = """
      <item>
        <title>Ep</title>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.description == ""
    end

    test "collapses whitespace in description" do
      xml = """
      <item>
        <title>Ep</title>
        <description>  Lots   of    spaces  </description>
        <enclosure url="https://example.com/ep.mp3" type="audio/mpeg" />
      </item>
      """

      [ep] = RssParser.parse_episodes(xml)
      assert ep.description == "Lots of spaces"
    end
  end

  # -- Episode limit --

  describe "parse_episodes/1 limits" do
    test "limits episodes to 150" do
      items =
        for i <- 1..200 do
          """
          <item>
            <title>Ep #{i}</title>
            <enclosure url="https://example.com/ep#{i}.mp3" type="audio/mpeg" />
          </item>
          """
        end

      xml = Enum.join(items)
      episodes = RssParser.parse_episodes(xml)
      assert length(episodes) == 150
    end
  end
end
