defmodule Tonie.Podcast.RssParser do
  @moduledoc """
  Parses podcast RSS/Atom feeds using regex-based extraction.
  Handles both plain text and CDATA-wrapped content.
  """

  def parse(xml) do
    # Split off the channel header (before the first <item>) for channel-level info
    channel_section =
      case String.split(xml, "<item", parts: 2) do
        [chan, _] -> chan
        [chan] -> chan
      end

    %{
      title: extract_text(channel_section, "title"),
      author:
        extract_text(channel_section, "itunes:author") ||
          extract_text(channel_section, "managingEditor"),
      thumbnail: extract_channel_image(channel_section),
      episodes: parse_episodes(xml)
    }
  end

  def parse_episodes(xml) do
    ~r/<item\b[^>]*>(.*?)<\/item>/s
    |> Regex.scan(xml, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&parse_item/1)
    |> Enum.filter(&(&1[:audio_url] != nil))
    |> Enum.take(150)
  end

  defp parse_item(xml) do
    %{
      title: extract_text(xml, "title"),
      pub_date: extract_text(xml, "pubDate") |> format_date(),
      duration: extract_text(xml, "itunes:duration") |> format_duration(),
      audio_url: extract_enclosure(xml),
      description: extract_description(xml)
    }
  end

  # ---

  defp extract_text(xml, tag) do
    cdata_re = Regex.compile!("<" <> tag <> "[^>]*><!\\[CDATA\\[(.*?)\\]\\]></" <> tag <> ">", "si")
    plain_re = Regex.compile!("<" <> tag <> "[^>]*>(.*?)</" <> tag <> ">", "si")

    case Regex.run(cdata_re, xml) do
      [_, text] ->
        text |> String.trim() |> decode_entities()

      _ ->
        case Regex.run(plain_re, xml) do
          [_, text] -> text |> String.replace(~r/<[^>]+>/, " ") |> String.trim() |> decode_entities()
          _ -> nil
        end
    end
  end

  defp extract_enclosure(xml) do
    # Prefer explicit audio/* MIME type
    url =
      case Regex.run(~r/<enclosure\s[^>]*url="([^"]+)"[^>]*type="audio\/[^"]*"/s, xml) do
        [_, url] ->
          url

        _ ->
          # Try reversed attribute order
          case Regex.run(~r/<enclosure\s[^>]*type="audio\/[^"]*"[^>]*url="([^"]+)"/s, xml) do
            [_, url] ->
              url

            _ ->
              # Fallback: any enclosure url
              case Regex.run(~r/<enclosure\s[^>]*url="([^"]+)"/, xml) do
                [_, url] -> url
                _ -> nil
              end
          end
      end

    decode_entities(url)
  end

  defp extract_channel_image(xml) do
    url =
      case Regex.run(~r/<itunes:image\s+href="([^"]+)"/, xml) do
        [_, url] ->
          url

        _ ->
          case Regex.run(~r/<itunes:image>\s*<url>([^<]+)<\/url>/, xml) do
            [_, url] ->
              String.trim(url)

            _ ->
              case Regex.run(~r/<image>\s*(?:<[^>]+>\s*)*<url>([^<]+)<\/url>/, xml) do
                [_, url] -> String.trim(url)
                _ -> nil
              end
          end
      end

    decode_entities(url)
  end

  defp extract_description(xml) do
    text =
      extract_text(xml, "description") ||
        extract_text(xml, "itunes:summary") ||
        ""

    text
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp format_date(nil), do: nil

  defp format_date(date_str) do
    # "Mon, 01 Jan 2024 10:00:00 +0000" → "01 Jan 2024"
    case Regex.run(~r/(\d{1,2}\s+\w{3}\s+\d{4})/, date_str) do
      [_, date] -> date
      _ -> date_str
    end
  end

  defp format_duration(nil), do: nil

  defp format_duration(dur) do
    dur = String.trim(dur)

    cond do
      dur == "" ->
        nil

      String.contains?(dur, ":") ->
        dur

      true ->
        case Integer.parse(dur) do
          {secs, ""} -> format_seconds(secs)
          _ -> dur
        end
    end
  end

  defp format_seconds(secs) do
    h = div(secs, 3600)
    m = secs |> rem(3600) |> div(60)
    s = rem(secs, 60)

    if h > 0 do
      "#{h}:#{pad(m)}:#{pad(s)}"
    else
      "#{m}:#{pad(s)}"
    end
  end

  defp pad(n), do: String.pad_leading(to_string(n), 2, "0")

  defp decode_entities(nil), do: nil

  defp decode_entities(str) do
    str
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
    |> then(&Regex.replace(~r/&#(\d+);/, &1, fn _, code ->
      <<String.to_integer(code)::utf8>>
    end))
    |> then(&Regex.replace(~r/&#x([0-9a-fA-F]+);/, &1, fn _, code ->
      <<String.to_integer(code, 16)::utf8>>
    end))
  end

end
