defmodule TonieWeb.Translations do
  @moduledoc """
  All user-facing strings in German and English.

  Usage: `t(:key)` or `t(:key, name: "value")` for interpolation.
  Language is set via the LANGUAGE environment variable (default: "de").
  """

  @translations %{
    # Search
    search_label: %{de: "Album suchen", en: "Search albums"},
    search_placeholder: %{
      de: "z.B. Paw Patrol, Globi, Schwiizergoofe...",
      en: "e.g. Paw Patrol, Frozen, Peppa Pig..."
    },
    no_results: %{
      de: "Keine Ergebnisse für \u00AB%{query}\u00BB",
      en: "No results for \u201C%{query}\u201D"
    },
    url_input: %{de: "URL direkt eingeben", en: "Enter URL directly"},

    # Tonie selector
    tonie_label: %{de: "Tonie wählen", en: "Select Tonie"},
    remaining: %{de: "%{time} verbleibend", en: "%{time} remaining"},
    no_chapters: %{de: "Keine Kapitel", en: "No chapters"},
    more_items: %{de: "+ %{count} mehr...", en: "+ %{count} more..."},

    # Upload mode
    mode_label: %{de: "Modus", en: "Mode"},
    prepend: %{de: "Am Anfang hinzufügen", en: "Add to beginning"},
    replace: %{de: "Alles ersetzen", en: "Replace all"},
    append: %{de: "Am Ende hinzufügen", en: "Add to end"},
    start_upload: %{de: "Start Upload", en: "Start Upload"},

    # Navigation
    back: %{de: "\u2190 Zurück", en: "\u2190 Back"},
    back_to_search: %{de: "\u2190 Zurück zur Suche", en: "\u2190 Back to search"},
    new_search: %{de: "Neue Suche", en: "New search"},

    # Content sections
    albums: %{de: "Alben", en: "Albums"},
    albums_link: %{de: "Alben \u2192", en: "Albums \u2192"},
    podcasts: %{de: "Podcasts", en: "Podcasts"},
    episodes_link: %{de: "Episoden \u2192", en: "Episodes \u2192"},
    details_link: %{de: "Details \u2192", en: "Details \u2192"},
    loading: %{de: "Wird geladen...", en: "Loading..."},
    no_albums_found: %{de: "Keine Alben gefunden", en: "No albums found"},
    no_episodes_found: %{de: "Keine Episoden gefunden", en: "No episodes found"},
    tracklist: %{de: "Tracklist", en: "Tracklist"},
    show_notes: %{de: "Show Notes", en: "Show Notes"},

    # Favorites
    save: %{de: "Merken", en: "Save"},

    # Tonie detail / chapter editor
    change: %{de: "Ändern", en: "Change"},
    select_all: %{de: "Alle", en: "All"},
    clear_selection: %{de: "Keine", en: "None"},
    tap_to_select: %{
      de: "Tippen zum Auswählen \u00B7 Gedrückt halten für Bereich",
      en: "Tap to select \u00B7 Long press for range"
    },
    tap_range_end: %{
      de: "Tippe auf den letzten Track des Bereichs",
      en: "Tap the last track in the range"
    },
    updating_chapters: %{de: "Kapitel werden aktualisiert...", en: "Updating chapters..."},
    chapters_updated: %{
      de: "Kapitel erfolgreich aktualisiert. Ohr 3 Sekunden halten zum Synchronisieren.",
      en: "Chapters updated successfully. Hold the ear for 3 seconds to sync."
    },
    chapters_error: %{
      de: "Fehler beim Aktualisieren der Kapitel.",
      en: "Error updating chapters."
    },

    # Status bar
    downloading: %{de: "Wird heruntergeladen...", en: "Downloading..."},
    uploading: %{de: "Wird hochgeladen...", en: "Uploading..."},
    completed: %{de: "Fertig!", en: "Done!"},
    error: %{de: "Fehler", en: "Error"},
    ready: %{de: "Bereit", en: "Ready"},

    # Worker messages
    job_started: %{de: "Auftrag gestartet!", en: "Job started!"},
    worker_busy: %{
      de: "Beschäftigt. Bitte warten bis der aktuelle Auftrag abgeschlossen ist.",
      en: "Worker is busy. Please wait for the current job to complete."
    },
    no_files: %{
      de: "Keine Dateien zum Hochladen. Bitte Download-Verzeichnis prüfen.",
      en: "No files to upload. Please check the download directory."
    },
    tonie_not_found: %{
      de: "Tonie nicht gefunden. Bitte einen Tonie auswählen.",
      en: "Tonie not found. Please select a tonie."
    },
    uploading_file: %{
      de: "Hochladen: %{name} (%{index}/%{total})...",
      en: "Uploading %{name} (%{index}/%{total})..."
    },
    downloading_files: %{
      de: "Herunterladen... %{count} Dateien bisher",
      en: "Downloading... %{count} files so far"
    },
    downloading_progress: %{
      de: "Herunterladen... %{count}/%{total} Dateien",
      en: "Downloading... %{count}/%{total} files"
    },
    upload_completed: %{
      de: "%{mode} abgeschlossen! %{count} Dateien hochgeladen.\nOhr 3 Sekunden halten zum Synchronisieren.",
      en: "%{mode} completed! Uploaded %{count} files.\nHold the ear for 3 seconds to sync."
    }
  }

  @doc "Look up a translated string by key, with optional interpolation bindings."
  def t(key, bindings \\ []) do
    lang = Application.get_env(:tonie, :language, :de)
    template = get_in(@translations, [key, lang]) || to_string(key)

    Enum.reduce(bindings, template, fn {k, v}, acc ->
      String.replace(acc, "%{#{k}}", to_string(v))
    end)
  end

  @doc "Returns the configured language as a string (for HTML lang attribute etc.)"
  def language, do: to_string(Application.get_env(:tonie, :language, :de))
end
