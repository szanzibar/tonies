defmodule Tonie.YTMusic.Parser do
  @moduledoc """
  Parses YouTube Music internal API responses into clean result maps.

  The API returns deeply nested JSON. This module extracts the relevant
  fields from search results (albums, artists) into flat maps.
  """

  @doc """
  Parses album search results from a YouTube Music API response.
  """
  @spec parse_albums(map()) :: [map()]
  def parse_albums(data) do
    data
    |> shelf_items()
    |> Enum.map(&parse_album_item/1)
  end

  @doc """
  Parses artist search results from a YouTube Music API response.
  """
  @spec parse_artists(map()) :: [map()]
  def parse_artists(data) do
    data
    |> shelf_items()
    |> Enum.map(&parse_artist_item/1)
  end

  @doc """
  Parses an artist page browse response.

  Returns a map with the artist's name, thumbnail, top albums from the carousel,
  and the browse params needed to fetch the full discography.
  """
  @spec parse_artist_page(map()) :: map()
  def parse_artist_page(data) do
    header =
      get_in(data, ["header", "musicImmersiveHeaderRenderer"]) ||
        get_in(data, ["header", "musicVisualHeaderRenderer"]) ||
        %{}

    name = get_in(header, ["title", "runs", Access.at(0), "text"])

    thumbnail =
      get_in(header, ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]) || []

    thumbnail_url = if thumbnail != [], do: List.last(thumbnail)["url"]

    sections = artist_page_sections(data)

    # Find the "Albums" carousel and extract its items + "more" params
    {albums, albums_browse_id, albums_params} = find_albums_carousel(sections)

    %{
      name: name,
      thumbnail: thumbnail_url,
      albums: albums,
      albums_browse_id: albums_browse_id,
      albums_params: albums_params
    }
  end

  @doc """
  Parses the full artist discography (grid of albums) from a browse response.
  """
  @spec parse_artist_albums(map()) :: [map()]
  def parse_artist_albums(data) do
    sections =
      get_in(data, [
        "contents",
        "singleColumnBrowseResultsRenderer",
        "tabs",
        Access.at(0),
        "tabRenderer",
        "content",
        "sectionListRenderer",
        "contents"
      ]) || []

    grid_section = Enum.find(sections, &(&1["gridRenderer"] != nil))
    items = get_in(grid_section, ["gridRenderer", "items"]) || []

    Enum.map(items, &parse_grid_album_item/1)
  end

  @doc """
  Parses album duration from an album browse response.

  The duration is in the `secondSubtitle` of the `musicResponsiveHeaderRenderer`,
  formatted as e.g. "4 songs • 3 minutes, 55 seconds".
  """
  @spec parse_album_duration(map()) :: map()
  def parse_album_duration(data) do
    header = album_browse_header(data)

    second_subtitle_runs = get_in(header, ["secondSubtitle", "runs"]) || []
    texts = Enum.map(second_subtitle_runs, & &1["text"]) |> Enum.reject(&(&1 == " • "))

    %{
      songs: List.first(texts),
      duration_text: List.last(texts)
    }
  end

  @doc """
  Parses full album details from an album browse response.

  Returns name, artist, year, thumbnail, and duration info.
  Used to restore album state from just an album_id.
  """
  @spec parse_album_page(map()) :: map()
  def parse_album_page(data) do
    header = album_browse_header(data) || %{}

    # Title
    title_runs = get_in(header, ["title", "runs"]) || []
    name = Enum.map_join(title_runs, "", & &1["text"])

    # Subtitle runs (type, year, artist)
    subtitle_runs = get_in(header, ["subtitle", "runs"]) || []

    # Find artist: run with a browse navigation endpoint
    artist_run =
      Enum.find(subtitle_runs, fn run ->
        get_in(run, ["navigationEndpoint", "browseEndpoint"]) != nil
      end)

    subtitle_texts =
      subtitle_runs
      |> Enum.map(& &1["text"])
      |> Enum.reject(&(&1 in [" • ", " · ", " & "]))

    artist = if artist_run, do: artist_run["text"], else: Enum.at(subtitle_texts, 1)
    year = Enum.find(subtitle_texts, &Regex.match?(~r/^\d{4}$/, &1 || ""))

    # Thumbnail
    thumbnails =
      get_in(header, ["thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"]) || []

    thumbnail = if thumbnails != [], do: List.last(thumbnails)["url"]

    # Duration (same as parse_album_duration)
    second_subtitle_runs = get_in(header, ["secondSubtitle", "runs"]) || []
    duration_texts = Enum.map(second_subtitle_runs, & &1["text"]) |> Enum.reject(&(&1 == " • "))

    %{
      name: if(name == "", do: nil, else: name),
      artist: artist,
      year: year,
      thumbnail: thumbnail,
      songs: List.first(duration_texts),
      duration_text: List.last(duration_texts),
      tracks: parse_album_tracks(data)
    }
  end

  defp parse_album_tracks(data) do
    contents =
      get_in(data, [
        "contents",
        "twoColumnBrowseResultsRenderer",
        "secondaryContents",
        "sectionListRenderer",
        "contents"
      ]) || []

    shelf =
      Enum.find_value(contents, fn c ->
        c["musicShelfRenderer"]
      end)

    items = (shelf && shelf["contents"]) || []

    Enum.map(items, fn item ->
      renderer = item["musicResponsiveListItemRenderer"]

      title =
        get_in(renderer, [
          "flexColumns",
          Access.at(0),
          "musicResponsiveListItemFlexColumnRenderer",
          "text",
          "runs",
          Access.at(0),
          "text"
        ])

      duration =
        get_in(renderer, [
          "fixedColumns",
          Access.at(0),
          "musicResponsiveListItemFixedColumnRenderer",
          "text",
          "runs",
          Access.at(0),
          "text"
        ])

      %{title: title, duration: duration}
    end)
  end

  defp album_browse_header(data) do
    sections =
      get_in(data, [
        "contents",
        "twoColumnBrowseResultsRenderer",
        "tabs",
        Access.at(0),
        "tabRenderer",
        "content",
        "sectionListRenderer",
        "contents"
      ]) || []

    Enum.find_value(sections, fn section ->
      section["musicResponsiveHeaderRenderer"]
    end)
  end

  # --- Album parsing ---

  defp parse_album_item(item) do
    renderer = item["musicResponsiveListItemRenderer"]
    col1_runs = col_runs(renderer, 1)
    non_separator_texts = texts_without_separators(col1_runs)
    artist_run = find_artist_run(col1_runs)

    %{
      name: first_text(col_runs(renderer, 0)),
      type: Enum.at(non_separator_texts, 0),
      artist: run_text(artist_run),
      artist_id: run_browse_id(artist_run),
      year: List.last(non_separator_texts),
      album_id: browse_id(renderer),
      playlist_id: overlay_playlist_id(renderer),
      thumbnail: largest_thumbnail(renderer)
    }
  end

  # --- Artist parsing ---

  defp parse_artist_item(item) do
    renderer = item["musicResponsiveListItemRenderer"]
    col1_texts = texts_without_separators(col_runs(renderer, 1))

    %{
      name: first_text(col_runs(renderer, 0)),
      artist_id: browse_id(renderer),
      subscribers: Enum.at(col1_texts, 1),
      thumbnail: largest_thumbnail(renderer)
    }
  end

  # --- Data extraction helpers ---

  defp shelf_items(data) do
    items =
      get_in(data, [
        "contents",
        "tabbedSearchResultsRenderer",
        "tabs",
        Access.at(0),
        "tabRenderer",
        "content",
        "sectionListRenderer",
        "contents"
      ]) || []

    shelf = Enum.find(items, &(&1["musicShelfRenderer"] != nil))
    get_in(shelf, ["musicShelfRenderer", "contents"]) || []
  end

  defp col_runs(renderer, index) do
    get_in(renderer, [
      "flexColumns",
      Access.at(index),
      "musicResponsiveListItemFlexColumnRenderer",
      "text",
      "runs"
    ]) || []
  end

  defp texts_without_separators(runs) do
    runs
    |> Enum.map(& &1["text"])
    |> Enum.reject(&(&1 == " • "))
  end

  defp first_text([]), do: nil
  defp first_text(runs), do: get_in(runs, [Access.at(0), "text"])

  defp find_artist_run(runs) do
    Enum.find(runs, fn run ->
      page_type =
        get_in(run, [
          "navigationEndpoint",
          "browseEndpoint",
          "browseEndpointContextSupportedConfigs",
          "browseEndpointContextMusicConfig",
          "pageType"
        ])

      is_binary(page_type) && String.contains?(page_type, "ARTIST")
    end)
  end

  defp run_text(nil), do: nil
  defp run_text(run), do: run["text"]

  defp run_browse_id(nil), do: nil

  defp run_browse_id(run) do
    get_in(run, ["navigationEndpoint", "browseEndpoint", "browseId"])
  end

  defp browse_id(renderer) do
    get_in(renderer, ["navigationEndpoint", "browseEndpoint", "browseId"])
  end

  defp overlay_playlist_id(renderer) do
    get_in(renderer, [
      "overlay",
      "musicItemThumbnailOverlayRenderer",
      "content",
      "musicPlayButtonRenderer",
      "playNavigationEndpoint",
      "watchPlaylistEndpoint",
      "playlistId"
    ])
  end

  defp largest_thumbnail(renderer) do
    thumbnails =
      get_in(renderer, [
        "thumbnail",
        "musicThumbnailRenderer",
        "thumbnail",
        "thumbnails"
      ]) || []

    case thumbnails do
      [_ | _] -> List.last(thumbnails)["url"]
      _ -> nil
    end
  end

  # --- Artist page helpers ---

  defp artist_page_sections(data) do
    get_in(data, [
      "contents",
      "singleColumnBrowseResultsRenderer",
      "tabs",
      Access.at(0),
      "tabRenderer",
      "content",
      "sectionListRenderer",
      "contents"
    ]) || []
  end

  defp find_albums_carousel(sections) do
    carousel =
      Enum.find(sections, fn section ->
        case section["musicCarouselShelfRenderer"] do
          nil ->
            false

          c ->
            title =
              get_in(c, [
                "header",
                "musicCarouselShelfBasicHeaderRenderer",
                "title",
                "runs",
                Access.at(0),
                "text"
              ])

            title == "Albums"
        end
      end)

    case carousel do
      nil ->
        {[], nil, nil}

      %{"musicCarouselShelfRenderer" => c} ->
        items = c["contents"] || []
        albums = Enum.map(items, &parse_carousel_album_item/1)

        # Extract the "more" button's browse params for full discography
        more_endpoint =
          get_in(c, [
            "header",
            "musicCarouselShelfBasicHeaderRenderer",
            "moreContentButton",
            "buttonRenderer",
            "navigationEndpoint",
            "browseEndpoint"
          ])

        browse_id = more_endpoint && more_endpoint["browseId"]
        params = more_endpoint && more_endpoint["params"]

        {albums, browse_id, params}
    end
  end

  defp parse_carousel_album_item(%{"musicTwoRowItemRenderer" => tr}) do
    title = get_in(tr, ["title", "runs", Access.at(0), "text"])
    subtitle_runs = get_in(tr, ["subtitle", "runs"]) || []
    subtitle_texts = subtitle_runs |> Enum.map(& &1["text"]) |> Enum.reject(&(&1 == " • "))

    browse_id = get_in(tr, ["navigationEndpoint", "browseEndpoint", "browseId"])

    playlist_id =
      get_in(tr, [
        "thumbnailOverlay",
        "musicItemThumbnailOverlayRenderer",
        "content",
        "musicPlayButtonRenderer",
        "playNavigationEndpoint",
        "watchPlaylistEndpoint",
        "playlistId"
      ])

    thumbnails =
      get_in(tr, ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]) || []

    thumbnail_url = if thumbnails != [], do: List.last(thumbnails)["url"]

    year = List.last(subtitle_texts)

    %{
      name: title,
      type: List.first(subtitle_texts),
      year: year,
      album_id: browse_id,
      playlist_id: playlist_id,
      thumbnail: thumbnail_url
    }
  end

  defp parse_carousel_album_item(_), do: %{}

  defp parse_grid_album_item(%{"musicTwoRowItemRenderer" => tr}) do
    title = get_in(tr, ["title", "runs", Access.at(0), "text"])
    subtitle_runs = get_in(tr, ["subtitle", "runs"]) || []
    subtitle_texts = subtitle_runs |> Enum.map(& &1["text"]) |> Enum.reject(&(&1 == " • "))

    browse_id = get_in(tr, ["navigationEndpoint", "browseEndpoint", "browseId"])

    playlist_id =
      get_in(tr, [
        "thumbnailOverlay",
        "musicItemThumbnailOverlayRenderer",
        "content",
        "musicPlayButtonRenderer",
        "playNavigationEndpoint",
        "watchPlaylistEndpoint",
        "playlistId"
      ])

    thumbnails =
      get_in(tr, ["thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"]) || []

    thumbnail_url = if thumbnails != [], do: List.last(thumbnails)["url"]

    year = List.last(subtitle_texts)
    type = List.first(subtitle_texts)

    %{
      name: title,
      type: type,
      year: year,
      album_id: browse_id,
      playlist_id: playlist_id,
      thumbnail: thumbnail_url
    }
  end

  defp parse_grid_album_item(_), do: %{}
end
