defmodule Tonie.YTMusic do
  @moduledoc """
  YouTube Music search client.

  Calls YouTube Music's internal API directly using Req + Jason.
  No external dependencies beyond what the app already uses.

  ## Usage

      {:ok, client} = Tonie.YTMusic.new()
      {:ok, albums} = Tonie.YTMusic.search_albums(client, "paw patrol dino")
      {:ok, artists} = Tonie.YTMusic.search_artists(client, "globi")

  Each album result includes a `playlist_id` that can be passed directly
  to yt-dlp as `https://music.youtube.com/playlist?list=PLAYLIST_ID`.
  """

  alias Tonie.YTMusic.Parser

  @base_url "https://music.youtube.com"
  @search_path "/youtubei/v1/search"

  # Filter params extracted from YouTube Music's web client.
  # These are base64-encoded protobuf that tell the API which result type to return.
  @filter_params %{
    albums: "Eg-KAQwIABAAGAEgACgAMABqChAEEAMQCRAFEAo%3D",
    artists: "Eg-KAQwIABAAGAAgASgAMABqChAEEAMQCRAFEAo%3D",
    songs: "Eg-KAQwIARAAGAAgACgAMABqChAEEAMQCRAFEAo%3D",
    playlists: "Eg-KAQwIABAAGAAgACgBMABqChAEEAMQCRAFEAo%3D"
  }

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  defstruct [:api_key, :client_name, :client_version, :visitor_data]

  @type t :: %__MODULE__{
          api_key: String.t(),
          client_name: String.t(),
          client_version: String.t(),
          visitor_data: String.t() | nil
        }

  @type album_result :: %{
          name: String.t() | nil,
          type: String.t() | nil,
          artist: String.t() | nil,
          artist_id: String.t() | nil,
          year: String.t() | nil,
          album_id: String.t() | nil,
          playlist_id: String.t() | nil,
          thumbnail: String.t() | nil
        }

  @type artist_result :: %{
          name: String.t() | nil,
          artist_id: String.t() | nil,
          subscribers: String.t() | nil,
          thumbnail: String.t() | nil
        }

  @doc """
  Initializes a new client by fetching API config from the YouTube Music homepage.
  """
  @spec new() :: {:ok, t()} | {:error, term()}
  def new do
    headers = base_headers()

    case Req.get(@base_url <> "/", headers: headers) do
      {:ok, %{body: body}} when is_binary(body) ->
        config = extract_config(body)

        case config["INNERTUBE_API_KEY"] do
          nil ->
            {:error, :missing_api_key}

          api_key ->
            {:ok,
             %__MODULE__{
               api_key: api_key,
               client_name: config["INNERTUBE_CLIENT_NAME"] || "WEB_REMIX",
               client_version: config["INNERTUBE_CLIENT_VERSION"] || "1.0",
               visitor_data: config["VISITOR_DATA"]
             }}
        end

      {:ok, resp} ->
        {:error, {:unexpected_response, resp.status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Searches YouTube Music for albums matching the query.

  Returns a list of album results with name, artist, year, thumbnail,
  and a `playlist_id` suitable for passing to yt-dlp.
  """
  @spec search_albums(t(), String.t()) :: {:ok, [album_result()]} | {:error, term()}
  def search_albums(%__MODULE__{} = client, query) do
    with {:ok, data} <- search(client, query, :albums) do
      {:ok, Parser.parse_albums(data)}
    end
  end

  @doc """
  Searches YouTube Music for artists matching the query.
  """
  @spec search_artists(t(), String.t()) :: {:ok, [artist_result()]} | {:error, term()}
  def search_artists(%__MODULE__{} = client, query) do
    with {:ok, data} <- search(client, query, :artists) do
      {:ok, Parser.parse_artists(data)}
    end
  end

  @doc """
  Builds a YouTube Music playlist URL from a playlist ID.

  This URL can be passed directly to yt-dlp for downloading.
  """
  @spec playlist_url(String.t()) :: String.t()
  def playlist_url(playlist_id) do
    "https://music.youtube.com/playlist?list=#{playlist_id}"
  end

  @doc """
  Builds a YouTube Music artist browse URL from an artist ID.
  """
  @spec artist_url(String.t()) :: String.t()
  def artist_url(artist_id) do
    "https://music.youtube.com/channel/#{artist_id}"
  end

  # --- Private ---

  defp search(%__MODULE__{} = client, query, filter) do
    body = %{
      "context" => %{
        "client" => %{
          "clientName" => client.client_name,
          "clientVersion" => client.client_version,
          "gl" => "US",
          "hl" => "en"
        },
        "user" => %{}
      },
      "query" => query,
      "params" => Map.get(@filter_params, filter)
    }

    url = "#{@base_url}#{@search_path}?alt=json&key=#{client.api_key}"

    case Req.post(url, json: body, headers: search_headers(client)) do
      {:ok, %{status: 200, body: data}} when is_map(data) ->
        {:ok, data}

      {:ok, %{status: status}} ->
        {:error, {:api_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_config(html) do
    Regex.scan(~r/ytcfg\.set\((\{.*?\})\)/s, html)
    |> Enum.reduce(%{}, fn [_, json], acc ->
      case Jason.decode(json) do
        {:ok, parsed} -> Map.merge(acc, parsed)
        _ -> acc
      end
    end)
  end

  defp base_headers do
    [
      {"user-agent", @user_agent},
      {"accept-language", "en-US,en;q=0.5"}
    ]
  end

  defp search_headers(%__MODULE__{} = client) do
    base_headers() ++
      [
        {"x-goog-visitor-id", client.visitor_data || ""},
        {"x-origin", @base_url},
        {"content-type", "application/json"},
        {"referer", @base_url <> "/"}
      ]
  end
end
