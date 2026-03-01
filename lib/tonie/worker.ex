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
    upload_mode: :replace,
    api_state: nil
  }
  @download_dir "./downloads"

  # Client API

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_job(youtube_url, tonie_id, upload_mode \\ :replace) do
    GenServer.call(__MODULE__, {:start_job, youtube_url, tonie_id, upload_mode})
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
  def handle_call({:start_job, youtube_url, tonie_id, upload_mode}, _from, state) do
    api_state = Api.init()

    broadcast_status(%{
      status: :downloading,
      message: "Downloading from YouTube...",
      progress: 10
    })

    task = Task.async(fn -> YtDlp.download(youtube_url) end)
    # task = Task.async(fn -> Process.sleep(5000) end)

    Process.send_after(self(), :check_job, 1_000)

    {:reply, :ok,
     %{state | task: task, tonie_id: tonie_id, upload_mode: upload_mode, api_state: api_state}}
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
            message: "No files to upload. Please check the download directory.",
            progress: 0
          }

        {_, nil} ->
          %{
            status: :idle,
            message: "Tonie not found. Please select a tonie.",
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
            progress = 90 + trunc(10 * index / total_files)
            file_name = Path.basename(file)

            broadcast_status(%{
              status: :uploading,
              message: "Uploading #{file_name} (#{index + 1}/#{total_files})...",
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
            message: "#{mode_label} completed! Uploaded #{total_files} files.",
            progress: 100
          }
      end

    broadcast_status(status)
    new_state = Map.merge(@empty_state, status)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_job, %{task: nil} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_job, state) do
    # Update status with current download count
    # Cap at 90% for downloads
    download_count = count_downloads()
    progress = min(10 + download_count * 5, 90)

    message = "Downloading... #{download_count} files so far"
    broadcast_status(%{status: :downloading, message: message, progress: progress})

    if Process.alive?(state.task.pid) do
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

  defp count_downloads() do
    File.ls!(@download_dir) |> length()
  end
end
