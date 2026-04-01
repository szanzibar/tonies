defmodule TonieWeb.ChapterEditor do
  @moduledoc """
  Handles chapter editing events: selection, reordering, deletion.
  Delegated to from YoutubeUploaderLive.
  """

  import Phoenix.Component, only: [assign: 2]
  import TonieWeb.Translations
  alias Tonie.Api

  @chapter_events ~w(
    toggle_chapter long_press_chapter select_all_chapters clear_chapter_selection
    move_chapters_up move_chapters_down move_chapters_top move_chapters_bottom
    save_chapter_order discard_chapter_changes remove_selected_chapters
  )

  def chapter_event?(event), do: event in @chapter_events

  def handle_event("toggle_chapter", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    case socket.assigns.range_start do
      nil ->
        selected = socket.assigns.selected_chapter_indices

        selected =
          if MapSet.member?(selected, index),
            do: MapSet.delete(selected, index),
            else: MapSet.put(selected, index)

        {:noreply, assign(socket, selected_chapter_indices: selected)}

      range_start when is_integer(range_start) ->
        {lo, hi} = Enum.min_max([range_start, index])
        new_indices = MapSet.new(lo..hi)
        selected = MapSet.union(socket.assigns.selected_chapter_indices, new_indices)
        {:noreply, assign(socket, selected_chapter_indices: selected, range_start: nil)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("long_press_chapter", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    selected = MapSet.put(socket.assigns.selected_chapter_indices, index)
    {:noreply, assign(socket, range_start: index, selected_chapter_indices: selected)}
  end

  def handle_event("select_all_chapters", _params, socket) do
    {chapters, _selected} = current_chapters_and_selection(socket)
    count = length(chapters)

    {:noreply,
     assign(socket, selected_chapter_indices: MapSet.new(0..(count - 1)), range_start: nil)}
  end

  def handle_event("clear_chapter_selection", _params, socket) do
    {:noreply, assign(socket, selected_chapter_indices: MapSet.new(), range_start: nil)}
  end

  def handle_event("move_chapters_up", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, new_selected} = move_selection(chapters, selected, :up)

    {:noreply,
     assign(socket, working_chapters: new_chapters, selected_chapter_indices: new_selected)}
  end

  def handle_event("move_chapters_down", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, new_selected} = move_selection(chapters, selected, :down)

    {:noreply,
     assign(socket, working_chapters: new_chapters, selected_chapter_indices: new_selected)}
  end

  def handle_event("move_chapters_top", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, _new_selected} = move_to_edge(chapters, selected, :top)

    {:noreply,
     assign(socket,
       working_chapters: new_chapters,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

  def handle_event("move_chapters_bottom", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)
    {new_chapters, _new_selected} = move_to_edge(chapters, selected, :bottom)

    {:noreply,
     assign(socket,
       working_chapters: new_chapters,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

  def handle_event("save_chapter_order", _params, socket) do
    tonie = selected_tonie(socket)

    send(self(), {:do_save_chapters, tonie, socket.assigns.working_chapters})

    {:noreply,
     assign(socket,
       selected_chapter_indices: MapSet.new(),
       range_start: nil,
       working_chapters: nil,
       status: :uploading,
       message: t(:updating_chapters)
     )}
  end

  def handle_event("discard_chapter_changes", _params, socket) do
    {:noreply,
     assign(socket,
       working_chapters: nil,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

  def handle_event("remove_selected_chapters", _params, socket) do
    {chapters, selected} = current_chapters_and_selection(socket)

    remaining_chapters =
      chapters
      |> Enum.with_index()
      |> Enum.reject(fn {_ch, i} -> MapSet.member?(selected, i) end)
      |> Enum.map(fn {ch, _i} -> ch end)

    {:noreply,
     assign(socket,
       working_chapters: remaining_chapters,
       selected_chapter_indices: MapSet.new(),
       range_start: nil
     )}
  end

  # --- handle_info for saving chapters to API ---

  def handle_save_chapters({_msg, tonie, chapters}, socket) do
    token = Api.auth()
    household_id = Api.get_household(token)

    case Api.update_chapters(token, household_id, tonie, chapters) do
      :ok ->
        api_state = Api.init()

        {:noreply,
         assign(socket,
           tonies: api_state.tonies,
           working_chapters: nil,
           status: :idle,
           message: t(:chapters_updated),
           progress: 100
         )}

      _ ->
        {:noreply,
         assign(socket,
           status: :error,
           message: t(:chapters_error)
         )}
    end
  end

  # --- Private helpers ---

  defp selected_tonie(socket) do
    Enum.find(socket.assigns.tonies, &(&1["id"] == socket.assigns.selected_tonie_id))
  end

  defp current_chapters_and_selection(socket) do
    tonie = selected_tonie(socket)
    chapters = socket.assigns.working_chapters || tonie["chapter_data"]
    {chapters, socket.assigns.selected_chapter_indices}
  end

  defp move_selection(chapters, selected, direction) do
    sorted =
      selected
      |> MapSet.to_list()
      |> Enum.sort(if direction == :up, do: :asc, else: :desc)

    max_idx = length(chapters) - 1

    Enum.reduce(sorted, {chapters, MapSet.new()}, fn idx, {chs, new_sel} ->
      neighbor = if direction == :up, do: idx - 1, else: idx + 1

      if neighbor < 0 or neighbor > max_idx or MapSet.member?(new_sel, neighbor) do
        {chs, MapSet.put(new_sel, idx)}
      else
        item = Enum.at(chs, idx)
        other = Enum.at(chs, neighbor)

        new_chs =
          chs
          |> List.replace_at(idx, other)
          |> List.replace_at(neighbor, item)

        {new_chs, MapSet.put(new_sel, neighbor)}
      end
    end)
  end

  defp move_to_edge(chapters, selected, direction) do
    selected_sorted = selected |> MapSet.to_list() |> Enum.sort()
    selected_items = Enum.map(selected_sorted, &Enum.at(chapters, &1))

    remaining =
      chapters
      |> Enum.with_index()
      |> Enum.reject(fn {_ch, i} -> MapSet.member?(selected, i) end)
      |> Enum.map(fn {ch, _i} -> ch end)

    new_chapters =
      case direction do
        :top -> selected_items ++ remaining
        :bottom -> remaining ++ selected_items
      end

    count = length(selected_items)

    new_selected =
      case direction do
        :top -> MapSet.new(0..(count - 1))
        :bottom -> MapSet.new((length(chapters) - count)..(length(chapters) - 1))
      end

    {new_chapters, new_selected}
  end
end
