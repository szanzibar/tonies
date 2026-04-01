defmodule TonieWeb.ChapterEditorTest do
  use ExUnit.Case, async: true

  alias TonieWeb.ChapterEditor

  # Build a minimal LiveView socket with the assigns the chapter editor needs.
  defp build_socket(opts \\ []) do
    chapters = opts[:chapters] || [
      %{"title" => "Track A", "file" => "a.mp3"},
      %{"title" => "Track B", "file" => "b.mp3"},
      %{"title" => "Track C", "file" => "c.mp3"},
      %{"title" => "Track D", "file" => "d.mp3"}
    ]

    tonie = %{
      "id" => "tonie-1",
      "chapter_data" => chapters,
      "chapters" => Enum.map(chapters, & &1["title"])
    }

    assigns =
      %{
        __changed__: %{},
        tonies: [tonie],
        selected_tonie_id: "tonie-1",
        working_chapters: opts[:working_chapters],
        selected_chapter_indices: opts[:selected] || MapSet.new(),
        range_start: opts[:range_start],
        status: :idle,
        message: ""
      }

    %Phoenix.LiveView.Socket{assigns: assigns}
  end

  defp titles(socket) do
    chapters = socket.assigns.working_chapters || hd(socket.assigns.tonies)["chapter_data"]
    Enum.map(chapters, & &1["title"])
  end

  defp selected(socket), do: socket.assigns.selected_chapter_indices

  # --- Toggle selection ---

  describe "toggle_chapter" do
    test "selects an unselected chapter" do
      socket = build_socket()
      {:noreply, socket} = ChapterEditor.handle_event("toggle_chapter", %{"index" => "1"}, socket)
      assert MapSet.member?(selected(socket), 1)
    end

    test "deselects a selected chapter" do
      socket = build_socket(selected: MapSet.new([1]))
      {:noreply, socket} = ChapterEditor.handle_event("toggle_chapter", %{"index" => "1"}, socket)
      refute MapSet.member?(selected(socket), 1)
    end

    test "toggling multiple chapters accumulates selection" do
      socket = build_socket()
      {:noreply, socket} = ChapterEditor.handle_event("toggle_chapter", %{"index" => "0"}, socket)
      {:noreply, socket} = ChapterEditor.handle_event("toggle_chapter", %{"index" => "2"}, socket)
      assert selected(socket) == MapSet.new([0, 2])
    end
  end

  # --- Range selection ---

  describe "long_press_chapter + toggle for range" do
    test "long press starts range, toggle completes it" do
      socket = build_socket()

      {:noreply, socket} =
        ChapterEditor.handle_event("long_press_chapter", %{"index" => "1"}, socket)

      assert socket.assigns.range_start == 1
      assert MapSet.member?(selected(socket), 1)

      {:noreply, socket} = ChapterEditor.handle_event("toggle_chapter", %{"index" => "3"}, socket)

      assert socket.assigns.range_start == nil
      assert selected(socket) == MapSet.new([1, 2, 3])
    end

    test "range works in reverse direction" do
      socket = build_socket()

      {:noreply, socket} =
        ChapterEditor.handle_event("long_press_chapter", %{"index" => "3"}, socket)

      {:noreply, socket} = ChapterEditor.handle_event("toggle_chapter", %{"index" => "1"}, socket)
      assert selected(socket) == MapSet.new([1, 2, 3])
    end
  end

  # --- Select all / clear ---

  describe "select_all_chapters" do
    test "selects all chapters" do
      socket = build_socket()
      {:noreply, socket} = ChapterEditor.handle_event("select_all_chapters", %{}, socket)
      assert selected(socket) == MapSet.new([0, 1, 2, 3])
    end
  end

  describe "clear_chapter_selection" do
    test "clears all selections" do
      socket = build_socket(selected: MapSet.new([0, 1, 2]))
      {:noreply, socket} = ChapterEditor.handle_event("clear_chapter_selection", %{}, socket)
      assert selected(socket) == MapSet.new()
    end
  end

  # --- Move up/down ---

  describe "move_chapters_up" do
    test "moves selected chapter up by one" do
      socket = build_socket(selected: MapSet.new([2]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_up", %{}, socket)

      assert titles(socket) == ["Track A", "Track C", "Track B", "Track D"]
      assert selected(socket) == MapSet.new([1])
    end

    test "does not move past the top" do
      socket = build_socket(selected: MapSet.new([0]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_up", %{}, socket)

      assert titles(socket) == ["Track A", "Track B", "Track C", "Track D"]
      assert selected(socket) == MapSet.new([0])
    end

    test "moves adjacent selected chapters together" do
      socket = build_socket(selected: MapSet.new([1, 2]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_up", %{}, socket)

      assert titles(socket) == ["Track B", "Track C", "Track A", "Track D"]
      assert selected(socket) == MapSet.new([0, 1])
    end
  end

  describe "move_chapters_down" do
    test "moves selected chapter down by one" do
      socket = build_socket(selected: MapSet.new([1]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_down", %{}, socket)

      assert titles(socket) == ["Track A", "Track C", "Track B", "Track D"]
      assert selected(socket) == MapSet.new([2])
    end

    test "does not move past the bottom" do
      socket = build_socket(selected: MapSet.new([3]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_down", %{}, socket)

      assert titles(socket) == ["Track A", "Track B", "Track C", "Track D"]
      assert selected(socket) == MapSet.new([3])
    end
  end

  # --- Move to top/bottom ---

  describe "move_chapters_top" do
    test "moves selected chapters to the top" do
      socket = build_socket(selected: MapSet.new([2, 3]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_top", %{}, socket)

      assert titles(socket) == ["Track C", "Track D", "Track A", "Track B"]
    end

    test "moves non-adjacent chapters to top preserving relative order" do
      socket = build_socket(selected: MapSet.new([1, 3]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_top", %{}, socket)

      assert titles(socket) == ["Track B", "Track D", "Track A", "Track C"]
    end
  end

  describe "move_chapters_bottom" do
    test "moves selected chapters to the bottom" do
      socket = build_socket(selected: MapSet.new([0, 1]))
      {:noreply, socket} = ChapterEditor.handle_event("move_chapters_bottom", %{}, socket)

      assert titles(socket) == ["Track C", "Track D", "Track A", "Track B"]
    end
  end

  # --- Remove ---

  describe "remove_selected_chapters" do
    test "removes selected chapters" do
      socket = build_socket(selected: MapSet.new([1, 3]))
      {:noreply, socket} = ChapterEditor.handle_event("remove_selected_chapters", %{}, socket)

      assert titles(socket) == ["Track A", "Track C"]
      assert selected(socket) == MapSet.new()
    end

    test "removing all chapters leaves empty list" do
      socket = build_socket(selected: MapSet.new([0, 1, 2, 3]))
      {:noreply, socket} = ChapterEditor.handle_event("remove_selected_chapters", %{}, socket)

      assert titles(socket) == []
    end
  end

  # --- Discard ---

  describe "discard_chapter_changes" do
    test "resets working_chapters and selection" do
      socket =
        build_socket(
          working_chapters: [%{"title" => "Modified", "file" => "x.mp3"}],
          selected: MapSet.new([0])
        )

      {:noreply, socket} = ChapterEditor.handle_event("discard_chapter_changes", %{}, socket)

      assert socket.assigns.working_chapters == nil
      assert selected(socket) == MapSet.new()
    end
  end
end
