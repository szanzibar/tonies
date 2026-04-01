defmodule Tonie.Podcast do
  require Logger

  @itunes_search_url "https://itunes.apple.com/search"
  @api_timeout 10_000
  @download_dir "./downloads"

  def search(query) do
    params = %{
      term: query,
      media: "podcast",
      entity: "podcast",
      limit: 10
    }

    case Req.get(@itunes_search_url, params: params, receive_timeout: @api_timeout) do
      {:ok, %{status: 200, body: body}} ->
        decoded = if is_map(body), do: body, else: Jason.decode!(body)

        results =
          (decoded["results"] || [])
          |> Enum.filter(&(&1["feedUrl"] != nil))
          |> Enum.map(&parse_podcast/1)
          |> Enum.filter(& &1)

        {:ok, results}

      error ->
        Logger.warning("Podcast search failed: #{inspect(error)}")
        {:error, :search_failed}
    end
  end

  def get_episodes(feed_url) do
    case Req.get(feed_url,
           receive_timeout: @api_timeout,
           headers: [{"user-agent", "Tonie/1.0"}],
           decode_body: false
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        xml = if is_binary(body), do: body, else: to_string(body)
        {:ok, Tonie.Podcast.RssParser.parse(xml)}

      error ->
        Logger.warning("Podcast feed fetch failed for #{feed_url}: #{inspect(error)}")
        {:error, :feed_failed}
    end
  end

  def download_episode(url, podcast_name \\ nil, episode_title \\ nil) do
    ext =
      url
      |> URI.parse()
      |> Map.get(:path, "")
      |> Path.extname()
      |> then(fn e -> if e == "", do: ".mp3", else: e end)

    filename =
      [podcast_name, episode_title]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&sanitize_for_filename/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" - ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()
      |> String.slice(0, 120)
      |> then(fn
        "" -> "episode"
        name -> name
      end)
      |> Kernel.<>(ext)

    dest = Path.join(@download_dir, filename)
    File.mkdir_p!(@download_dir)

    case Req.get(url,
           into: File.stream!(dest),
           receive_timeout: 600_000,
           headers: [{"user-agent", "Tonie/1.0"}]
         ) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, filename}

      error ->
        File.rm(dest)
        {:error, "Download failed: #{inspect(error)}"}
    end
  end

  @doc false
  def sanitize_for_filename(str) when is_binary(str) do
    # Ensure valid UTF-8 — if the binary contains invalid sequences (e.g. from a
    # Latin-1 encoded feed), strip the high bytes rather than letting PCRE
    # partially consume multi-byte sequences and leave orphaned lead bytes.
    str =
      if String.valid?(str) do
        str
      else
        for <<byte <- str>>, byte < 128, into: "", do: <<byte>>
      end

    # Keep only characters safe for cross-platform filenames
    str
    |> String.replace(~r/[^a-zA-Z0-9 \-_.]/, "")
    |> String.trim()
  end

  # ---

  defp parse_podcast(result) do
    with id when not is_nil(id) <- result["collectionId"],
         name when not is_nil(name) <- result["collectionName"],
         feed_url when not is_nil(feed_url) <- result["feedUrl"] do
      %{
        podcast_id: to_string(id),
        name: name,
        author: result["artistName"],
        thumbnail: result["artworkUrl600"] || result["artworkUrl100"],
        feed_url: feed_url,
        episode_count: result["trackCount"]
      }
    else
      _ -> nil
    end
  end
end
