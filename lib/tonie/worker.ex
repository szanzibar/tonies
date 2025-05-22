defmodule Tonie.Worker do
  use GenServer
  require Logger
  alias Phoenix.PubSub
  alias Tonie.YtDlp
  alias Tonie.Api

  @topic "youtube_worker"

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
    {:ok, %{status: :idle, message: "Ready", progress: 0}}
  end

  @impl true
  def handle_call({:start_job, youtube_url, tonie_id}, _from, state) do
    case state.status do
      :idle ->
        # Start job in a separate process to keep GenServer responsive
        Process.send(self(), {:process_job, youtube_url, tonie_id}, [])

        new_state = %{
          status: :downloading,
          message: "Starting download...",
          progress: 0,
          youtube_url: youtube_url,
          tonie_id: tonie_id
        }

        broadcast_status(new_state)
        {:reply, :ok, new_state}

      _busy ->
        {:reply, {:error, :busy}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:process_job, youtube_url, tonie_id}, state) do
    # Initialize API connection
    api_state = Api.init()

    # Update status to downloading
    update_status(:downloading, "Downloading from YouTube...", 10)

    # Download file
    case YtDlp.download(youtube_url) do
      {:ok, _download_meta} ->
        download_dir = "./downloads"

        # Get all mp3 files in sorted order (assumed to be numbered sequentially)
        files =
          File.ls!(download_dir)
          |> Enum.sort()
          |> Enum.map(fn file -> Path.join(download_dir, file) end)

        tonie = Enum.find(api_state.tonies, fn t -> t["id"] == tonie_id end)

        # Clear the tonie before uploading
        Api.clear_creative_tonie(api_state.token, api_state.household_id, tonie)

        # Upload each file sequentially
        total_files = length(files)

        Enum.with_index(files, fn file, index ->
          # Calculate progress based on file position
          # 50% for download done + up to 50% for upload progress
          progress = 50 + trunc(50 * index / total_files)
          file_name = Path.basename(file)

          update_status(
            :uploading,
            "Uploading #{file_name} (#{index + 1}/#{total_files})...",
            progress
          )

          # Upload the file
          Api.upload_file(api_state.token, api_state.household_id, tonie, file)
        end)

        # After all uploads, clean up the files
        Enum.each(files, fn file ->
          File.rm!(file)
        end)

        update_status(
          :completed,
          "Upload completed successfully! Uploaded #{length(files)} files.",
          100
        )

      {:error, reason} ->
        update_status(:error, "Download failed: #{reason}", 0)
    end

    # Reset status after some time
    Process.send_after(self(), :reset_status, 5_000)

    {:noreply, state}
  end

  @impl true
  def handle_info(:reset_status, _state) do
    new_state = %{status: :idle, message: "Ready", progress: 0}
    broadcast_status(new_state)
    {:noreply, new_state}
  end

  # Helper functions

  defp update_status(status, message, progress) do
    new_state = %{status: status, message: message, progress: progress}
    broadcast_status(new_state)
    GenServer.cast(__MODULE__, {:update_state, new_state})
  end

  @impl true
  def handle_cast({:update_state, new_state}, _state) do
    {:noreply, new_state}
  end

  defp broadcast_status(status) do
    PubSub.broadcast(Tonie.PubSub, @topic, {:status_update, status})
  end
end
