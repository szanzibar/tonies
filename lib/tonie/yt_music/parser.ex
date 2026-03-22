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
end
