defmodule TonieWeb.PodcastComponents do
  @moduledoc """
  Components for podcasts. Mirrors the music components layout:
  podcast_browse = artist_browse, episode_detail = album_detail,
  show notes = tracklist.
  """

  use Phoenix.Component
  import TonieWeb.ComponentHelpers
  import TonieWeb.Translations

  # --- Episode detail (mirrors album_detail) ---

  def episode_detail(assigns) do
    ~H"""
    <div class="mb-2 flex items-center gap-3">
      <button
        type="button"
        phx-click="back_from_episode"
        class="text-xs text-blue-600 hover:text-blue-800"
      >
        {t(:back)}
      </button>
      <button
        type="button"
        phx-click="clear_podcast"
        class="text-xs text-gray-400 hover:text-gray-600"
      >
        {t(:new_search)}
      </button>
    </div>

    <div class="bg-purple-50 border-2 border-purple-300 rounded-lg overflow-hidden">
      <div
        class="flex gap-4 p-4 cursor-pointer active:bg-purple-100 transition-colors"
        phx-click="toggle_show_notes"
      >
        <div class="w-32 h-32 sm:w-40 sm:h-40 rounded-lg overflow-hidden bg-gray-100 flex-shrink-0 shadow-md">
          <img
            :if={@browsing_podcast && @browsing_podcast.thumbnail}
            src={thumb(@browsing_podcast.thumbnail)}
            class="w-full h-full object-cover"
          />
        </div>
        <div class="flex flex-col justify-center min-w-0">
          <p class="font-semibold text-base sm:text-lg leading-tight">
            {@selected_episode.title}
          </p>
          <p class="text-sm text-gray-500 mt-1">
            {if @browsing_podcast, do: @browsing_podcast.name, else: ""}
          </p>
          <p :if={@selected_episode.pub_date} class="text-xs text-gray-400 mt-0.5">
            {@selected_episode.pub_date}
          </p>
          <p :if={@selected_episode.duration} class="text-xs text-gray-400 mt-2">
            {@selected_episode.duration}
          </p>
          <p
            :if={@selected_episode.description && @selected_episode.description != ""}
            class="text-xs text-purple-400 mt-1"
          >
            {if @show_notes, do: "▾", else: "▸"} {t(:show_notes)}
          </p>
        </div>
      </div>

      <%= if @show_notes do %>
        <div class="border-t border-purple-200 px-4 py-3">
          <p class="text-sm text-gray-600 leading-relaxed whitespace-pre-line">
            {@selected_episode.description}
          </p>
        </div>
      <% end %>
    </div>
    <input type="hidden" name="youtube_url" value={@youtube_url} />
    """
  end

  # --- Podcast browse (mirrors artist_browse) ---

  def podcast_browse(assigns) do
    podcast_saved =
      Enum.any?(
        assigns.saved_podcasts,
        &(&1["podcast_id"] == assigns.browsing_podcast.podcast_id)
      )

    assigns = assign(assigns, :podcast_saved, podcast_saved)

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
        :if={@browsing_podcast.thumbnail}
        src={thumb(@browsing_podcast.thumbnail)}
        class="w-10 h-10 rounded-lg object-cover flex-shrink-0"
      />
      <div class="flex-1 min-w-0">
        <p class="font-medium text-sm">{@browsing_podcast.name}</p>
        <p class="text-xs text-gray-400">{@browsing_podcast.author}</p>
      </div>
      <button
        :if={!@podcast_saved && @browsing_podcast.name}
        type="button"
        phx-click="save_podcast"
        class="text-gray-300 hover:text-yellow-500 text-lg flex-shrink-0"
        title={t(:save)}
      >
        ☆
      </button>
      <span :if={@podcast_saved} class="text-yellow-400 text-lg flex-shrink-0">★</span>
    </div>

    <%= if @loading_podcast do %>
      <div class="flex justify-center py-8">
        <div class="w-6 h-6 border-2 border-blue-400 border-t-transparent rounded-full animate-spin" />
      </div>
    <% else %>
      <div class="max-h-[40rem] overflow-y-auto space-y-1.5">
        <%= for {episode, index} <- Enum.with_index(@podcast_episodes) do %>
          <button
            type="button"
            phx-click="select_episode"
            phx-value-index={index}
            class="w-full flex items-center gap-3 p-2.5 hover:bg-gray-50 rounded-lg text-left transition-colors border border-gray-200"
          >
            <div class="flex-1 min-w-0">
              <p class="text-sm font-medium line-clamp-2 leading-snug">{episode.title}</p>
              <p class="text-xs text-gray-400 mt-0.5">
                {episode.pub_date}
                {if episode.duration, do: " · #{episode.duration}"}
              </p>
            </div>
            <span class="text-xs text-purple-500 flex-shrink-0">{t(:details_link)}</span>
          </button>
        <% end %>
      </div>
      <p :if={@podcast_episodes == []} class="text-xs text-gray-400 text-center py-4">
        {t(:no_episodes_found)}
      </p>
    <% end %>
    """
  end
end
