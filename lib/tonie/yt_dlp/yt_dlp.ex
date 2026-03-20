defmodule Tonie.YtDlp do
  require Logger

  def get_track_count(url) do
    path = binaries_path()
    yt_dlp_path = Path.join(path, "yt-dlp") |> Path.expand() |> prepare_executable()

    case System.cmd(yt_dlp_path, ["--no-warnings", "--flat-playlist", "--print", "id", url],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        count = output |> String.trim() |> String.split("\n") |> Enum.count(&(&1 != ""))
        max(count, 1)

      _ ->
        1
    end
  end

  def download(url) do
    path = binaries_path()
    path |> inspect |> Logger.debug()
    yt_dlp_path = Path.join(path, "yt-dlp") |> Path.expand() |> prepare_executable()
    ffmpeg_path = Path.join(path, "ffmpeg") |> Path.expand() |> prepare_executable()

    update_yt_dlp(yt_dlp_path)

    options =
      arguments([
        {"format", "bestaudio[vcodec=none]"},
        {"paths", "home:./downloads"},
        {"output", "%(playlist_index)s-%(title)s.%(ext)s"},
        {"ffmpeg-location", ffmpeg_path}
      ]) ++ [url]

    case System.cmd(yt_dlp_path, options, stderr_to_stdout: true) do
      {"", error} -> {:error, error}
      {error, 2} -> {:error, error}
      {meta, 0} -> {:ok, meta}
      {meta, 1} -> {:error, meta}
    end
  end

  defp arguments(options) do
    options
    |> Enum.reduce([], fn
      {k, v}, acc -> acc ++ ["--#{k}", v]
      argument, acc -> ["--#{argument}" | acc]
    end)
  end

  defp prepare_executable(path) do
    File.chmod!(path, 0o755)
    path
  end

  defp update_yt_dlp(path) do
    System.cmd(path, ["-U"], stderr_to_stdout: true) |> inspect() |> Logger.debug()
  end

  defp binaries_path do
    case :os.type() do
      {:unix, :darwin} -> "./binaries/mac/"
      {:unix, :linux} -> "./binaries/linux/"
    end
  end
end
