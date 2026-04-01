defmodule TonieWeb.MusicComponents do
  @moduledoc """
  Components for YouTube Music: album detail, artist browse, album grid.
  """

  use Phoenix.Component
  import TonieWeb.ComponentHelpers
  import TonieWeb.Translations

  # --- Album detail ---

  def album_detail(assigns) do
    ~H"""
    <div class="mb-2 flex items-center gap-3">
      <button
        type="button"
        phx-click="back_from_album"
        class="text-xs text-blue-600 hover:text-blue-800"
      >
        {t(:back)}
      </button>
      <button
        type="button"
        phx-click="clear_album"
        class="text-xs text-gray-400 hover:text-gray-600"
      >
        {t(:new_search)}
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
            <p class="text-xs text-gray-400 animate-pulse mt-2">{t(:loading)}</p>
          <% else %>
            <p :if={@album_duration} class="text-xs text-gray-400 mt-2">
              {@album_duration.songs} · {@album_duration.duration_text}
            </p>
          <% end %>
          <p class="text-xs text-blue-400 mt-1">
            {if @show_tracks, do: "▾", else: "▸"} {t(:tracklist)}
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
          &(&1["artist_id"] ==
              (assigns.browsing_artist.artist_id || assigns.browsing_artist[:artist_id]))
        )
      )

    ~H"""
    <div class="mb-3">
      <button
        type="button"
        phx-click="back_to_search"
        class="text-xs text-blue-600 hover:text-blue-800"
      >
        {t(:back_to_search)}
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
        title={t(:save)}
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
        {t(:no_albums_found)}
      </p>
    <% end %>
    """
  end

  # --- Album grid ---

  attr :id, :string, required: true
  attr :albums, :list, required: true

  def album_grid(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="LazyImages"
      class="grid grid-cols-3 sm:grid-cols-4 gap-2 sm:gap-3 max-h-[40rem] overflow-y-auto"
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
end
