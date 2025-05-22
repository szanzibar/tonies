defmodule Tonie.Worker do
  use GenServer
  require Logger
  alias Phoenix.PubSub
  alias Tonie.YtDlp
  alias Tonie.Api

  @topic "youtube_worker"
  @empty_state %{
    status: :idle,
    message: "Ready",
    progress: 0,
    task: nil,
    tonie_id: nil,
    api_state: nil
  }
  @download_dir "./downloads"

  # Client API

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_job(youtube_url, tonie_id) do
    GenServer.call(__MODULE__, {:start_job, youtube_url, tonie_id})
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
  def handle_call({:start_job, youtube_url, tonie_id}, _from, state) do
    api_state = Api.init()

    broadcast_status(%{
      status: :downloading,
      message: "Downloading from YouTube...",
      progress: 10
    })

    task = Task.async(fn -> YtDlp.download(youtube_url) end)
    # task = Task.async(fn -> Process.sleep(5000) end)

    Process.send_after(self(), :check_job, 1_000)

    {:reply, :ok, %{state | task: task, tonie_id: tonie_id, api_state: api_state}}
  end

  @impl true
  def handle_info(:handle_upload, state) do
    files =
      File.ls!(@download_dir)
      |> Enum.sort()
      |> Enum.map(fn file -> Path.join(@download_dir, file) end)
      |> dbg

    tonie = Enum.find(state.api_state.tonies, fn t -> t["id"] == state.tonie_id end) |> dbg

    # Clear the tonie before uploading
    Api.clear_creative_tonie(state.api_state.token, state.api_state.household_id, tonie) |> dbg

    # Upload each file sequentially
    total_files = length(files)

    Enum.with_index(files, fn file, index ->
      # Calculate progress based on file position
      # 90% for download done + up to 10% for upload progress
      progress = 90 + trunc(10 * index / total_files)
      file_name = Path.basename(file)

      broadcast_status(%{
        status: :uploading,
        message: "Uploading #{file_name} (#{index + 1}/#{total_files})...",
        progress: progress
      })

      # Upload the file
      Api.upload_file(state.api_state.token, state.api_state.household_id, tonie, file)
    end)

    # After all uploads, clean up the files
    Enum.each(files, fn file ->
      File.rm!(file)
    end)

    status = %{
      status: :completed,
      message: "Upload completed successfully! Uploaded #{length(files)} files.",
      progress: 100
    }

    new_state = Map.merge(state, status)
    broadcast_status(status)
    Process.send_after(self(), :reset_status, 5_000)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_job, state) do
    download_count =
      File.ls!(@download_dir) |> Enum.filter(&String.ends_with?(&1, ".mp3")) |> length()

    # Update status with current download count
    # Cap at 90% for downloads
    progress = min(10 + download_count * 5, 90)
    message = "Downloading... #{download_count} files so far"
    broadcast_status(%{status: :downloading, message: message, progress: progress})

    if Process.alive?(state.task.pid) |> dbg do
      Process.send_after(self(), :check_job, 1_000)
    else
      Process.send_after(self(), :handle_upload, 100)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:reset_status, _state) do
    broadcast_status(%{status: :idle, message: "Ready", progress: 0})
    {:noreply, @empty_state}
  end

  def handle_info(msg, state) do
    Logger.debug("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp broadcast_status(%{status: _, message: _, progress: _} = status_map) do
    PubSub.broadcast(Tonie.PubSub, @topic, {:status_update, status_map})
  end
end
