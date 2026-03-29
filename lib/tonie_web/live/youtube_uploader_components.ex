defmodule TonieWeb.YoutubeUploaderComponents do
  @moduledoc """
  Function components for the YoutubeUploaderLive view.
  """

  use Phoenix.Component

  # --- Navigation ---

  def nav_bar(assigns) do
    ~H"""
    <div class="mb-4 flex flex-wrap items-center gap-1.5">
      <button
        type="button"
        phx-click="go_home"
        class="flex items-center justify-center w-7 h-7 rounded-full bg-gray-100 hover:bg-gray-200 text-sm"
      >
        🏠
      </button>
      <%= for artist <- Enum.sort_by(@saved_artists, & &1["name"]) do %>
        <div class="group flex items-center gap-1 pl-1 pr-1.5 py-0.5 bg-gray-100 rounded-full text-xs hover:bg-gray-200 transition-colors">
          <img
            :if={artist["thumbnail"]}
            src={thumb(artist["thumbnail"])}
            class="w-5 h-5 rounded-full object-cover"
          />
          <button
            type="button"
            phx-click="select_saved_artist"
            phx-value-artist_id={artist["artist_id"]}
            class="text-gray-700 hover:text-gray-900 max-w-[8rem] truncate"
          >
            {artist["name"]}
          </button>
          <button
            type="button"
            phx-click="remove_saved_artist"
            phx-value-artist_id={artist["artist_id"]}
            class="text-gray-300 hover:text-red-400 ml-0.5"
          >
            ✕
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Album detail ---

  def album_detail(assigns) do
    ~H"""
    <div class="mb-2 flex items-center gap-3">
      <button
        type="button"
        phx-click="back_from_album"
        class="text-xs text-blue-600 hover:text-blue-800"
      >
        ← Zurück
      </button>
      <button
        type="button"
        phx-click="clear_album"
        class="text-xs text-gray-400 hover:text-gray-600"
      >
        Neue Suche
      </button>
    </div>

    <div class="bg-blue-50 border-2 border-blue-300 rounded-lg overflow-hidden">
      <div
        class="flex gap-4 p-4 cursor-pointer active:bg-blue-100 transition-colors"
        phx-click="toggle_tracks"
      >
        <div class="w-32 h-32 sm:w-40 sm:h-40 rounded-lg overflow-hidden bg-gray-100 flex-shrink-0 shadow-md">
          <img
            :if={@selected_album.thumbnail}
            src={thumb(@selected_album.thumbnail)}
            class="w-full h-full object-cover"
          />
        </div>
        <div class="flex flex-col justify-center min-w-0">
          <p class="font-semibold text-base sm:text-lg leading-tight">
            {@selected_album.name}
          </p>
          <p class="text-sm text-gray-500 mt-1">
            {if @browsing_artist, do: @browsing_artist.name, else: @selected_album[:artist]}
          </p>
          <p :if={@selected_album.year} class="text-xs text-gray-400 mt-0.5">
            {@selected_album.year}
          </p>
          <%= if @loading_duration do %>
            <p class="text-xs text-gray-400 animate-pulse mt-2">Wird geladen...</p>
          <% else %>
            <p :if={@album_duration} class="text-xs text-gray-400 mt-2">
              {@album_duration.songs} · {@album_duration.duration_text}
            </p>
          <% end %>
          <p class="text-xs text-blue-400 mt-1">
            {if @show_tracks, do: "▾", else: "▸"} Tracklist
          </p>
        </div>
      </div>

      <%= if @show_tracks do %>
        <%= if @loading_duration do %>
          <div class="border-t border-blue-200 px-4 py-3 flex justify-center">
            <div class="w-4 h-4 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
          </div>
        <% else %>
          <%= if @album_duration && @album_duration[:tracks] != [] do %>
            <div class="border-t border-blue-200 px-4 py-3">
              <ol class="space-y-1">
                <%= for {track, i} <- Enum.with_index(@album_duration[:tracks] || []) do %>
                  <li class="flex items-baseline gap-2 text-sm">
                    <span class="text-xs text-gray-400 w-5 text-right flex-shrink-0">
                      {i + 1}
                    </span>
                    <span class="flex-1 truncate">{track.title}</span>
                    <span class="text-xs text-gray-400 flex-shrink-0">{track.duration}</span>
                  </li>
                <% end %>
              </ol>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    <input type="hidden" name="youtube_url" value={@youtube_url} />
    """
  end

  # --- Artist browse ---

  def artist_browse(assigns) do
    assigns =
      assign(assigns, :artist_saved,
        Enum.any?(
          assigns.saved_artists,
          &(&1["artist_id"] == (assigns.browsing_artist.artist_id || assigns.browsing_artist[:artist_id]))
        )
      )

    ~H"""
    <div class="mb-3">
      <button
        type="button"
        phx-click="back_to_search"
        class="text-xs text-blue-600 hover:text-blue-800"
      >
        ← Zurück zur Suche
      </button>
    </div>

    <div class="flex items-center gap-3 p-3 bg-gray-50 rounded-lg mb-3">
      <img
        :if={@browsing_artist.thumbnail}
        src={thumb(@browsing_artist.thumbnail)}
        class="w-10 h-10 rounded-full object-cover flex-shrink-0"
      />
      <div class="flex-1 min-w-0">
        <p class="font-medium text-sm">{@browsing_artist.name}</p>
        <p class="text-xs text-gray-400">{@browsing_artist.subscribers}</p>
      </div>
      <button
        :if={!@artist_saved && @browsing_artist.name}
        type="button"
        phx-click="save_artist"
        class="text-gray-300 hover:text-yellow-500 text-lg flex-shrink-0"
        title="Merken"
      >
        ☆
      </button>
      <span :if={@artist_saved} class="text-yellow-400 text-lg flex-shrink-0">
        ★
      </span>
    </div>

    <%= if @loading_artist do %>
      <div class="flex justify-center py-8">
        <div class="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
      </div>
    <% else %>
      <.album_grid id="artist-albums" albums={@artist_albums} />
      <p :if={@artist_albums == []} class="text-xs text-gray-400 text-center py-4">
        Keine Alben gefunden
      </p>
    <% end %>
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
        placeholder="z.B. Paw Patrol, Globi, Schwiizergoofe..."
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
          <span class="text-xs text-blue-500 flex-shrink-0">Alben →</span>
        </button>
      <% end %>
    </div>

    <%!-- Album results --%>
    <div :if={@search_results != [] && !@searching} class="mt-3">
      <p class="text-xs text-gray-400 mb-2">Alben</p>
      <.album_grid id="search-albums" albums={@search_results} />
    </div>

    <p
      :if={@search_query != "" && @search_results == [] && @artist_results == [] && !@searching}
      class="mt-2 text-xs text-gray-400"
    >
      Keine Ergebnisse für «{@search_query}»
    </p>

    <%!-- URL fallback --%>
    <div class="mt-3">
      <button
        type="button"
        phx-click="toggle_url_input"
        class="text-xs text-gray-400 hover:text-gray-600"
      >
        {if @show_url_input, do: "▾", else: "▸"} URL direkt eingeben
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
                  <span>{format_duration(tonie["secondsRemaining"])} remaining</span>
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
                <p class="text-xs sm:text-sm text-gray-500 italic">Keine Kapitel</p>
              <% else %>
                <ul class="list-disc list-inside text-xs sm:text-sm text-gray-600">
                  <%= for chapter <- Enum.take(tonie["chapters"], 3) do %>
                    <li class="w-full truncate">{chapter}</li>
                  <% end %>
                  <%= if length(tonie["chapters"]) > 3 do %>
                    <li class="text-gray-500 italic">
                      + {length(tonie["chapters"]) - 3} mehr...
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
                Alle
              </button>
              <button
                type="button"
                phx-click="clear_chapter_selection"
                disabled={!@has_selection}
                class={"w-full h-10 flex items-center justify-center rounded text-xs #{if @has_selection, do: @btn_enabled, else: @btn_disabled}"}
              >
                Keine
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
                Tippen zum Auswählen · Gedrückt halten für Bereich
              </p>
            <% end %>
          <% end %>
        </div>

        <%!-- Right column: info + chapters --%>
        <div class="flex-1 min-w-0 w-full">
          <div class="flex justify-between items-center mb-1">
            <div class="flex-1">
              <div class="flex justify-between text-xs text-gray-400 mb-0.5">
                <span>{format_duration(@tonie["secondsRemaining"])} remaining</span>
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
              Ändern
            </button>
          </div>
          <input type="hidden" name="tonie_id" value={@tonie["id"]} />
          <%= if Enum.empty?(@tonie["chapters"]) do %>
            <p class="text-xs sm:text-sm text-gray-500 italic mt-2">Keine Kapitel</p>
          <% else %>
            <div class="mt-2">
              <p :if={is_integer(@range_start)} class="text-xs text-orange-600 mb-1 animate-pulse">
                Tippe auf den letzten Track des Bereichs
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

  # --- Shared sub-components ---

  attr :id, :string, required: true
  attr :albums, :list, required: true

  defp album_grid(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="LazyImages"
      class="grid grid-cols-3 sm:grid-cols-4 gap-2 sm:gap-3 max-h-[28rem] overflow-y-auto"
    >
      <%= for {album, index} <- Enum.with_index(@albums) do %>
        <button
          type="button"
          phx-click="select_album"
          phx-value-index={index}
          class="group text-left transition-all hover:scale-[1.03] active:scale-100"
        >
          <div class="aspect-square rounded-lg overflow-hidden bg-gray-100 shadow-sm group-hover:shadow-md transition-shadow">
            <img
              :if={album.thumbnail}
              data-src={thumb(album.thumbnail)}
              class="w-full h-full object-cover"
            />
          </div>
          <p class="mt-1 text-xs font-medium leading-tight line-clamp-2">{album.name}</p>
          <p class="text-[10px] text-gray-400 truncate">
            {if album[:artist], do: "#{album.artist} · "}
            {album.year}
          </p>
        </button>
      <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp thumb(url) when is_binary(url) do
    "/thumb/" <> Base.url_encode64(url, padding: false)
  end

  defp thumb(_), do: nil

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

  defp status_label(:downloading), do: "Wird heruntergeladen..."
  defp status_label(:uploading), do: "Wird hochgeladen..."
  defp status_label(:completed), do: "Fertig!"
  defp status_label(:error), do: "Fehler"
  defp status_label(_), do: "Bereit"
end
