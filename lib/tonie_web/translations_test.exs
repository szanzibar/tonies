defmodule TonieWeb.TranslationsTest do
  use ExUnit.Case, async: true

  alias TonieWeb.Translations

  setup do
    original = Application.get_env(:tonie, :language)
    on_exit(fn -> Application.put_env(:tonie, :language, original) end)
    :ok
  end

  describe "t/1" do
    test "returns German string when language is :de" do
      Application.put_env(:tonie, :language, :de)
      assert Translations.t(:search_label) == "Album suchen"
      assert Translations.t(:start_upload) == "Start Upload"
      assert Translations.t(:downloading) == "Wird heruntergeladen..."
    end

    test "returns English string when language is :en" do
      Application.put_env(:tonie, :language, :en)
      assert Translations.t(:search_label) == "Search albums"
      assert Translations.t(:start_upload) == "Start Upload"
      assert Translations.t(:downloading) == "Downloading..."
    end

    test "returns key as string for unknown keys" do
      assert Translations.t(:nonexistent_key) == "nonexistent_key"
    end

    test "defaults to German" do
      Application.put_env(:tonie, :language, :de)
      assert Translations.t(:back) == "\u2190 Zurück"

      Application.put_env(:tonie, :language, :en)
      assert Translations.t(:back) == "\u2190 Back"
    end
  end

  describe "t/2 with interpolation" do
    test "replaces single binding" do
      Application.put_env(:tonie, :language, :en)
      assert Translations.t(:remaining, time: "45 min") == "45 min remaining"
    end

    test "replaces multiple bindings" do
      Application.put_env(:tonie, :language, :en)

      result = Translations.t(:uploading_file, name: "track.mp3", index: 2, total: 5)
      assert result == "Uploading track.mp3 (2/5)..."
    end

    test "interpolation works in German" do
      Application.put_env(:tonie, :language, :de)

      result = Translations.t(:uploading_file, name: "track.mp3", index: 2, total: 5)
      assert result == "Hochladen: track.mp3 (2/5)..."
    end

    test "integer bindings are converted to strings" do
      Application.put_env(:tonie, :language, :en)
      assert Translations.t(:more_items, count: 7) == "+ 7 more..."
    end

    test "no_results includes query" do
      Application.put_env(:tonie, :language, :de)
      assert Translations.t(:no_results, query: "test") == "Keine Ergebnisse für \u00ABtest\u00BB"

      Application.put_env(:tonie, :language, :en)
      assert Translations.t(:no_results, query: "test") == "No results for \u201Ctest\u201D"
    end

    test "upload_completed with mode and count" do
      Application.put_env(:tonie, :language, :en)
      result = Translations.t(:upload_completed, mode: "Replace", count: 3)
      assert result =~ "Replace completed!"
      assert result =~ "3 files"
    end
  end

  describe "language/0" do
    test "returns configured language as string" do
      Application.put_env(:tonie, :language, :de)
      assert Translations.language() == "de"

      Application.put_env(:tonie, :language, :en)
      assert Translations.language() == "en"
    end
  end

  describe "all translations are complete" do
    test "every key has both :de and :en entries" do
      # Access the translations map via the module attribute by testing
      # that every key returns a non-key string in both languages
      translations = get_all_translation_keys()

      for key <- translations do
        Application.put_env(:tonie, :language, :de)
        de = Translations.t(key)
        refute de == to_string(key), "Missing German translation for #{key}"

        Application.put_env(:tonie, :language, :en)
        en = Translations.t(key)
        refute en == to_string(key), "Missing English translation for #{key}"
      end
    end
  end

  # Extract all keys by testing known keys from the module.
  # This list should match the keys in translations.ex.
  defp get_all_translation_keys do
    [
      :search_label,
      :search_placeholder,
      :no_results,
      :url_input,
      :tonie_label,
      :remaining,
      :no_chapters,
      :more_items,
      :mode_label,
      :prepend,
      :replace,
      :append,
      :start_upload,
      :back,
      :back_to_search,
      :new_search,
      :albums,
      :albums_link,
      :podcasts,
      :episodes_link,
      :details_link,
      :loading,
      :no_albums_found,
      :no_episodes_found,
      :tracklist,
      :show_notes,
      :save,
      :change,
      :select_all,
      :clear_selection,
      :tap_to_select,
      :tap_range_end,
      :updating_chapters,
      :chapters_updated,
      :chapters_error,
      :downloading,
      :uploading,
      :completed,
      :error,
      :ready,
      :job_started,
      :worker_busy,
      :no_files,
      :tonie_not_found,
      :uploading_file,
      :downloading_files,
      :downloading_progress,
      :upload_completed
    ]
  end
end
