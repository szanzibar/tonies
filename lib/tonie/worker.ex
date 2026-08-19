defmodule Tonie.Worker do
  use GenServer
  require Logger
  alias Phoenix.PubSub
  alias Tonie.Api
  import TonieWeb.Translations

  @topic "youtube_worker"
  @empty_state %{
    status: :idle,
    message: "",
    progress: 0,
    task: nil,
    tonie_id: nil,
    upload_mode: :replace,
    api_state: nil,
    total_tracks: nil
  }
  @download_dir "./downloads"

  # Client API

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Starts a download + upload job.

  `download_opts` is a map with:
    - `:download_fn` (required) — zero-arity function that performs the download
    - `:track_count_fn` — zero-arity function that returns expected track count
    - `:total_tracks` — known track count (skips counting)
    - `:message` — initial status message (default: "Downloading...")
  """
  def start_job(tonie_id, upload_mode, download_opts) do
    GenServer.call(__MODULE__, {:start_job, tonie_id, upload_mode, download_opts})
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  # Server callbacks

  @impl true
  def init(_) do
    {:ok, @empty_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:start_job, tonie_id, upload_mode, opts}, _from, state) do
    api_state = Api.init()

    broadcast_status(%{
      status: :downloading,
      message: opts[:message] || t(:downloading),
      progress: 0
    })

    worker = self()

    cond do
      opts[:total_tracks] ->
        send(worker, {:track_count, opts[:total_tracks]})

      opts[:track_count_fn] ->
        Task.start(fn -> send(worker, {:track_count, opts.track_count_fn.()}) end)

      true ->
        :ok
    end

    task = Task.async(opts.download_fn)

    Process.send_after(self(), :check_job, 1_000)

    {:reply, :ok,
     %{
       state
       | task: task,
         tonie_id: tonie_id,
         upload_mode: upload_mode,
         api_state: api_state,
         total_tracks: opts[:total_tracks]
     }}
  end

  @impl true
  def handle_info(:handle_upload, state) do
    files =
      File.ls!(@download_dir)
      |> Enum.sort()
      |> Enum.map(fn file -> Path.join(@download_dir, file) end)

    status =
      case {files, Enum.find(state.api_state.tonies, &(&1["id"] == state.tonie_id))} do
        {[], _} ->
          %{
            status: :idle,
            message: t(:no_files),
            progress: 0
          }

        {_, nil} ->
          %{
            status: :idle,
            message: t(:tonie_not_found),
            progress: 0
          }

        {files, tonie} ->
          token = state.api_state.token
          household_id = state.api_state.household_id
          existing_chapters = tonie["chapter_data"] || []

          # For replace and prepend, clear existing chapters first
          if state.upload_mode in [:replace, :prepend] do
            Api.clear_creative_tonie(token, household_id, tonie)
          end

          total_files = length(files)

          Enum.with_index(files, fn file, index ->
            progress = 75 + trunc(25 * index / total_files)
            file_name = Path.basename(file)

            broadcast_status(%{
              status: :uploading,
              message: t(:uploading_file, name: file_name, index: index + 1, total: total_files),
              progress: progress
            })

            Api.upload_file(token, household_id, tonie, file)
          end)

          # For prepend, re-add the old chapters after the new ones
          if state.upload_mode == :prepend do
            Enum.each(existing_chapters, fn chapter ->
              Api.add_chapter(token, household_id, tonie, chapter["title"], chapter["file"])
            end)
          end

          Enum.each(files, fn file ->
            File.rm!(file)
          end)

          mode_label = String.capitalize(to_string(state.upload_mode))

          %{
            status: :idle,
            message: t(:upload_completed, mode: mode_label, count: total_files),
            progress: 100
          }
      end

    broadcast_status(status)
    new_state = Map.merge(@empty_state, status)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:track_count, total_tracks}, state) do
    download_count = count_downloads()
    progress = min(trunc(75 * download_count / total_tracks), 75)

    broadcast_status(%{
      status: :downloading,
      message: t(:downloading_progress, count: download_count, total: total_tracks),
      progress: progress
    })

    {:noreply, %{state | total_tracks: total_tracks}}
  end

  @impl true
  def handle_info(:check_job, %{task: nil} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_job, state) do
    download_count = count_downloads()

    {progress, message} =
      case state.total_tracks do
        nil ->
          {min(download_count * 5, 75), t(:downloading_files, count: download_count)}

        total ->
          {min(trunc(75 * download_count / total), 75),
           t(:downloading_progress, count: download_count, total: total)}
      end

    broadcast_status(%{status: :downloading, message: message, progress: progress})

    if Process.alive?(state.task.pid) do
      Process.send_after(self(), :check_job, 1_000)
    end

    {:noreply, state}
  end

  # Reply from the download task started via Task.async in :start_job
  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:error, output} ->
        Logger.error("Download failed: #{inspect(output)}")

        # ponytail: drop partial downloads; clear error beats silently uploading a partial album
        File.ls!(@download_dir) |> Enum.each(&File.rm!(Path.join(@download_dir, &1)))

        status = %{
          status: :idle,
          message: t(:download_failed, error: error_summary(output)),
          progress: 0
        }

        broadcast_status(status)
        {:noreply, Map.merge(@empty_state, status)}

      _ok ->
        send(self(), :handle_upload)
        {:noreply, %{state | task: nil}}
    end
  end

  @impl true
  def handle_info(:reset_status, _state) do
    broadcast_status(%{status: :idle, message: t(:ready), progress: 0})
    {:noreply, @empty_state}
  end

  def handle_info(msg, state) do
    Logger.debug("Received unexpected message: #{inspect(msg)}")

    broadcast_status(%{
      status: :idle,
      message: "Unexpected message received: #{inspect(msg)}",
      progress: 0
    })

    {:noreply, state}
  end

  defp broadcast_status(%{status: _, message: _, progress: _} = status_map) do
    PubSub.broadcast(Tonie.PubSub, @topic, {:status_update, status_map})
  end

  @doc false
  # Pull the ERROR lines out of yt-dlp output so the UI shows the cause, not a wall of text.
  def error_summary(output) when is_binary(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "ERROR"))
    |> Enum.uniq()
    |> case do
      [] -> output |> String.split("\n", trim: true) |> Enum.take(-3) |> Enum.join("\n")
      errors -> errors |> Enum.take(3) |> Enum.join("\n")
    end
  end

  def error_summary(other), do: inspect(other)

  defp count_downloads() do
    File.ls!(@download_dir) |> length()
  end
end
