defmodule Tonie.YtDlp do
  require Logger

  def download(url) do
    path = "./lib/tonie/yt_dlp/binaries/mac/"
    yt_dlp_path = Path.join(path, "yt-dlp") |> Path.expand() |> executable_path
    ffmpeg_path = Path.join(path, "ffmpeg") |> Path.expand() |> executable_path

    File.mkdir_p!(Path.expand("./downloads"))

    options =
      arguments([
        "extract-audio",
        {"audio-format", "mp3"},
        {"audio-quality", "0"},
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

  defp executable_path(path) do
    File.chmod!(path, 0o755)

    System.cmd(path, ["-U"], stderr_to_stdout: true) |> inspect() |> Logger.debug()

    path
  end
end
