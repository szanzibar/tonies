defmodule TonieWeb.YoutubeUploaderComponents do
  @moduledoc """
  Shared components: navigation, search panel, tonie management, status bar.
  """

  use Phoenix.Component
  import TonieWeb.ComponentHelpers
  import TonieWeb.MusicComponents, only: [album_grid: 1]
  import TonieWeb.Translations

  # --- Navigation ---

  def nav_bar(assigns) do
    combined =
      (Enum.map(assigns.saved_artists, &Map.put(&1, "_type", "artist")) ++
         Enum.map(assigns.saved_podcasts, &Map.put(&1, "_type", "podcast")))
      |> Enum.sort_by(& &1["name"])

    assigns = assign(assigns, :combined_favorites, combined)

    ~H"""
    <div class="mb-4 flex flex-wrap items-center gap-1.5">
      <button
        type="button"
        phx-click="go_home"
        class="flex items-center justify-center w-7 h-7 rounded-full bg-gray-100 hover:bg-gray-200 text-sm"
      >
        🏠
      </button>
      <%= for item <- @combined_favorites do %>
        <%= if item["_type"] == "artist" do %>
          <div class="group flex items-center gap-1 pl-1 pr-1.5 py-0.5 bg-gray-100 rounded-full text-xs hover:bg-gray-200 transition-colors">
            <img
              :if={item["thumbnail"]}
              src={thumb(item["thumbnail"])}
              class="w-5 h-5 rounded-full object-cover"
            />
            <button
              type="button"
              phx-click="select_saved_artist"
              phx-value-artist_id={item["artist_id"]}
              class="text-gray-700 hover:text-gray-900 max-w-[8rem] truncate"
            >
              {item["name"]}
            </button>
            <button
              type="button"
              phx-click="remove_saved_artist"
              phx-value-artist_id={item["artist_id"]}
              class="text-gray-300 hover:text-red-400 ml-0.5"
            >
              ✕
            </button>
          </div>
        <% else %>
          <div class="group flex items-center gap-1 pl-1 pr-1.5 py-0.5 bg-purple-50 rounded-full text-xs hover:bg-purple-100 transition-colors">
            <img
              :if={item["thumbnail"]}
              src={thumb(item["thumbnail"])}
              class="w-5 h-5 rounded-md object-cover"
            />
            <button
              type="button"
              phx-click="select_saved_podcast"
              phx-value-podcast_id={item["podcast_id"]}
              class="text-gray-700 hover:text-gray-900 max-w-[8rem] truncate"
            >
              {item["name"]}
            </button>
            <button
              type="button"
              phx-click="remove_saved_podcast"
              phx-value-podcast_id={item["podcast_id"]}
              class="text-gray-300 hover:text-red-400 ml-0.5"
            >
              ✕
            </button>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  # --- Search panel ---

  def search_panel(assigns) do
    ~H"""
    <div class="relative">
      <input
        type="text"
        value={@search_query}
        phx-keyup="search"
        name="query"
        autocomplete="off"
        class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm focus:ring-blue-500 focus:border-blue-500"
        placeholder={t(:search_placeholder)}
        phx-debounce="400"
      />
      <div :if={@searching} class="absolute right-3 top-1/2 -translate-y-1/2">
        <div class="w-4 h-4 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
      </div>
    </div>

    <%!-- Artist results --%>
    <div :if={@artist_results != [] && !@searching} class="mt-3">
      <%= for {artist, index} <- Enum.with_index(Enum.take(@artist_results, 3)) do %>
        <button
          type="button"
          phx-click="select_artist"
          phx-value-index={index}
          class="w-full flex items-center gap-3 p-2.5 hover:bg-gray-50 rounded-lg text-left transition-colors border border-gray-200 mb-1.5"
        >
          <img
            :if={artist.thumbnail}
            src={thumb(artist.thumbnail)}
            class="w-10 h-10 rounded-full object-cover flex-shrink-0"
          />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium truncate">{artist.name}</p>
            <p class="text-xs text-gray-400">{artist.subscribers}</p>
          </div>
          <span class="text-xs text-blue-500 flex-shrink-0">{t(:albums_link)}</span>
        </button>
      <% end %>
    </div>

    <%!-- Podcast results --%>
    <div :if={@podcast_results != [] && !@searching} class="mt-3">
      <p class="text-xs text-gray-400 mb-2">{t(:podcasts)}</p>
      <%= for {podcast, index} <- Enum.with_index(Enum.take(@podcast_results, 3)) do %>
        <button
          type="button"
          phx-click="select_podcast"
          phx-value-index={index}
          class="w-full flex items-center gap-3 p-2.5 hover:bg-gray-50 rounded-lg text-left transition-colors border border-gray-200 mb-1.5"
        >
          <img
            :if={podcast.thumbnail}
            src={thumb(podcast.thumbnail)}
            class="w-10 h-10 rounded-lg object-cover flex-shrink-0"
          />
          <div :if={!podcast.thumbnail} class="w-10 h-10 rounded-lg bg-purple-100 flex-shrink-0" />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium truncate">{podcast.name}</p>
            <p class="text-xs text-gray-400 truncate">{podcast.author}</p>
          </div>
          <span class="text-xs text-purple-500 flex-shrink-0">{t(:episodes_link)}</span>
        </button>
      <% end %>
    </div>

    <%!-- Album results --%>
    <div :if={@search_results != [] && !@searching} class="mt-3">
      <p class="text-xs text-gray-400 mb-2">{t(:albums)}</p>
      <.album_grid id="search-albums" albums={@search_results} />
    </div>

    <p
      :if={
        @search_query != "" && @search_results == [] && @artist_results == [] &&
          @podcast_results == [] && !@searching
      }
      class="mt-2 text-xs text-gray-400"
    >
      {t(:no_results, query: @search_query)}
    </p>

    <%!-- URL fallback --%>
    <div class="mt-3">
      <button
        type="button"
        phx-click="toggle_url_input"
        class="text-xs text-gray-400 hover:text-gray-600"
      >
        {if @show_url_input, do: "▾", else: "▸"} {t(:url_input)}
      </button>
      <div :if={@show_url_input} class="mt-1">
        <input
          type="text"
          name="youtube_url"
          value={@youtube_url}
          autocomplete="off"
          class="block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm"
          placeholder="https://music.youtube.com/playlist?list=..."
        />
      </div>
    </div>
    """
  end

  # --- Tonie selector (grid) ---

  def tonie_selector(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
      <%= for tonie <- @tonies do %>
        <div
          class="border-2 rounded-lg p-3 sm:p-4 cursor-pointer transition-all hover:bg-gray-50"
          phx-click="select_tonie"
          phx-value-id={tonie["id"]}
        >
          <div class="flex items-start space-x-3 sm:space-x-4">
            <img
              src={tonie["imageUrl"]}
              alt="Tonie"
              class="w-16 h-16 sm:w-24 sm:h-24 rounded object-cover flex-shrink-0"
            />
            <div class="flex-1 min-w-0 w-full">
              <div class="mb-1">
                <div class="flex justify-between text-xs text-gray-400 mb-0.5">
                  <span>{t(:remaining, time: format_duration(tonie["secondsRemaining"]))}</span>
                </div>
                <div class="w-full bg-gray-200 rounded-full h-1.5">
                  <div
                    class="bg-blue-500 h-1.5 rounded-full"
                    style={"width: #{usage_percent(tonie)}%"}
                  >
                  </div>
                </div>
              </div>
              <%= if Enum.empty?(tonie["chapters"]) do %>
                <p class="text-xs sm:text-sm text-gray-500 italic">{t(:no_chapters)}</p>
              <% else %>
                <ul class="list-disc list-inside text-xs sm:text-sm text-gray-600">
                  <%= for chapter <- Enum.take(tonie["chapters"], 3) do %>
                    <li class="w-full truncate">{chapter}</li>
                  <% end %>
                  <%= if length(tonie["chapters"]) > 3 do %>
                    <li class="text-gray-500 italic">
                      {t(:more_items, count: length(tonie["chapters"]) - 3)}
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Tonie detail with chapter editor ---

  def tonie_detail(assigns) do
    tonie = selected_tonie(assigns.tonies, assigns.selected_tonie_id)
    chapters = assigns.working_chapters || tonie["chapter_data"]
    has_selection = MapSet.size(assigns.selected_chapter_indices) > 0
    btn_enabled = "text-gray-600 bg-gray-100 hover:bg-gray-200 active:bg-gray-300"
    btn_disabled = "text-gray-300 bg-gray-50 cursor-default"

    assigns =
      assigns
      |> assign(:tonie, tonie)
      |> assign(:chapters, chapters)
      |> assign(:has_selection, has_selection)
      |> assign(:btn_enabled, btn_enabled)
      |> assign(:btn_disabled, btn_disabled)

    ~H"""
    <div class="border-2 border-blue-500 ring-2 ring-blue-200 rounded-lg p-3 sm:p-4">
      <div class="flex items-start space-x-3 sm:space-x-4">
        <%!-- Left column: tonie image + sticky controls --%>
        <div class="flex-shrink-0 sticky top-3 self-start">
          <img
            src={@tonie["imageUrl"]}
            alt="Tonie"
            class="w-16 h-16 sm:w-24 sm:h-24 rounded object-cover"
          />
          <%= if @has_selection || @working_chapters != nil do %>
            <div class="flex flex-col items-center gap-1.5 mt-2 w-16 sm:w-24">
              <button
                type="button"
                phx-click="move_chapters_top"
                disabled={!@has_selection}
                class={"w-full h-10 flex items-center justify-center rounded text-sm #{if @has_selection, do: @btn_enabled, else: @btn_disabled}"}
              >
                ⤒
              </button>
              <button
                type="button"
                phx-click="move_chapters_up"
                disabled={!@has_selection}
                class={"w-full h-10 flex items-center justify-center rounded text-sm #{if @has_selection, do: @btn_enabled, else: @btn_disabled}"}
              >
                ↑
              </button>
              <button
                type="button"
                phx-click="move_chapters_down"
                disabled={!@has_selection}
                class={"w-full h-10 flex items-center justify-center rounded text-sm #{if @has_selection, do: @btn_enabled, else: @btn_disabled}"}
              >
                ↓
              </button>
              <button
                type="button"
                phx-click="move_chapters_bottom"
                disabled={!@has_selection}
                class={"w-full h-10 flex items-center justify-center rounded text-sm #{if @has_selection, do: @btn_enabled, else: @btn_disabled}"}
              >
                ⤓
              </button>

              <div class="w-full border-t border-gray-200 my-1"></div>

              <button
                type="button"
                phx-click="select_all_chapters"
                class={"w-full h-10 flex items-center justify-center rounded text-xs #{@btn_enabled}"}
              >
                {t(:select_all)}
              </button>
              <button
                type="button"
                phx-click="clear_chapter_selection"
                disabled={!@has_selection}
                class={"w-full h-10 flex items-center justify-center rounded text-xs #{if @has_selection, do: @btn_enabled, else: @btn_disabled}"}
              >
                {t(:clear_selection)}
              </button>

              <div class="w-full border-t border-gray-200 my-1"></div>

              <button
                type="button"
                phx-click="remove_selected_chapters"
                disabled={!@has_selection}
                class={"w-full h-10 flex items-center justify-center rounded #{if @has_selection, do: "text-red-400 bg-red-50 hover:bg-red-100 active:bg-red-200", else: "text-red-200 bg-red-50/50 cursor-default"}"}
              >
                🗑
              </button>

              <%= if @working_chapters != nil do %>
                <div class="w-full border-t border-gray-200 my-1"></div>
                <button
                  type="button"
                  phx-click="save_chapter_order"
                  class="w-full h-10 flex items-center justify-center text-white bg-blue-600 rounded hover:bg-blue-700 active:bg-blue-800 text-sm font-medium"
                >
                  ✓
                </button>
                <button
                  type="button"
                  phx-click="discard_chapter_changes"
                  class="w-full h-10 flex items-center justify-center text-gray-400 bg-gray-100 rounded hover:bg-gray-200 text-xs"
                >
                  ✕
                </button>
              <% end %>
            </div>
          <% else %>
            <%= if not Enum.empty?(@tonie["chapters"]) do %>
              <p class="mt-2 text-[10px] text-gray-400 text-center w-16 sm:w-24 leading-tight">
                {t(:tap_to_select)}
              </p>
            <% end %>
          <% end %>
        </div>

        <%!-- Right column: info + chapters --%>
        <div class="flex-1 min-w-0 w-full">
          <div class="flex justify-between items-center mb-1">
            <div class="flex-1">
              <div class="flex justify-between text-xs text-gray-400 mb-0.5">
                <span>{t(:remaining, time: format_duration(@tonie["secondsRemaining"]))}</span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-1.5">
                <div
                  class="bg-blue-500 h-1.5 rounded-full"
                  style={"width: #{usage_percent(@tonie)}%"}
                >
                </div>
              </div>
            </div>
            <button
              type="button"
              phx-click="deselect_tonie"
              class="ml-3 text-xs text-blue-600 hover:text-blue-800 flex-shrink-0"
            >
              {t(:change)}
            </button>
          </div>
          <input type="hidden" name="tonie_id" value={@tonie["id"]} />
          <%= if Enum.empty?(@tonie["chapters"]) do %>
            <p class="text-xs sm:text-sm text-gray-500 italic mt-2">{t(:no_chapters)}</p>
          <% else %>
            <div class="mt-2">
              <p :if={is_integer(@range_start)} class="text-xs text-orange-600 mb-1 animate-pulse">
                {t(:tap_range_end)}
              </p>

              <div class="space-y-0.5">
                <%= for {chapter, i} <- Enum.with_index(@chapters) do %>
                  <% selected = MapSet.member?(@selected_chapter_indices, i) %>
                  <% is_range_start = @range_start == i %>
                  <div
                    id={"chapter-#{i}"}
                    phx-hook="LongPress"
                    phx-click="toggle_chapter"
                    phx-value-index={i}
                    data-index={i}
                    class={"flex items-center gap-2 w-full text-left px-2 py-1.5 rounded text-sm transition-colors select-none cursor-pointer #{cond do
                      is_range_start -> "bg-orange-100 text-orange-700 ring-1 ring-orange-300"
                      selected -> "bg-red-50 text-red-700"
                      true -> "hover:bg-gray-50 text-gray-700"
                    end}"}
                  >
                    <span class="flex-1 truncate">{chapter["title"]}</span>
                    <span
                      :if={selected && !is_range_start}
                      class="text-red-300 text-xs flex-shrink-0"
                    >
                      ✕
                    </span>
                    <span :if={is_range_start} class="text-orange-400 text-xs flex-shrink-0">
                      ↕
                    </span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # --- Status bar ---

  def status_bar(assigns) do
    ~H"""
    <div :if={@status != :idle || @progress > 0} class="mt-6 sm:mt-8">
      <div class="p-3 sm:p-4 border rounded-md">
        <div class="flex items-center justify-between mb-2">
          <span class={status_color(@status)}>{status_label(@status)}</span>
          <span class="text-sm">{@progress}%</span>
        </div>

        <div class="w-full bg-gray-200 rounded-full h-2.5">
          <div
            class="bg-blue-600 h-2.5 rounded-full transition-all"
            style={"width: #{@progress}%"}
          >
          </div>
        </div>

        <p
          :for={line <- String.split(@message, "\n")}
          class="mt-2 text-xs sm:text-sm text-gray-600 break-words"
        >
          {line}
        </p>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp format_duration(seconds) when is_number(seconds) do
    minutes = trunc(seconds / 60)
    "#{minutes} min"
  end

  defp format_duration(_), do: "0 min"

  defp usage_percent(tonie) do
    present = tonie["secondsPresent"] || 0
    remaining = tonie["secondsRemaining"] || 0
    total = present + remaining

    if total > 0, do: trunc(present / total * 100), else: 0
  end

  defp selected_tonie(tonies, tonie_id) do
    Enum.find(tonies, &(&1["id"] == tonie_id))
  end

  defp status_color(status) do
    base = "font-medium text-sm"

    case status do
      :idle -> "#{base} text-gray-500"
      :downloading -> "#{base} text-blue-500"
      :uploading -> "#{base} text-purple-500"
      :completed -> "#{base} text-green-500"
      :error -> "#{base} text-red-500"
      _ -> "#{base} text-gray-500"
    end
  end

  defp status_label(:downloading), do: t(:downloading)
  defp status_label(:uploading), do: t(:uploading)
  defp status_label(:completed), do: t(:completed)
  defp status_label(:error), do: t(:error)
  defp status_label(_), do: t(:ready)
end
