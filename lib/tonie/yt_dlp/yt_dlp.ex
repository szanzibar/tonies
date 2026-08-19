defmodule Tonie.YtDlp do
  require Logger

  def get_track_count(url) do
    path = binaries_path()
    yt_dlp_path = ensure_yt_dlp(path) |> prepare_executable()

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
    yt_dlp_path = ensure_yt_dlp(path) |> prepare_executable()

    update_yt_dlp(yt_dlp_path)

    options =
      arguments(
        [
          {"format", "bestaudio[vcodec=none]"},
          {"paths", "home:./downloads"},
          {"output", "%(playlist_index)s-%(title)s.%(ext)s"}
        ] ++ ffmpeg_location_args(path)
      ) ++ [url]

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

  # yt-dlp: download standalone binary from GitHub releases if missing

  defp ensure_yt_dlp(binaries_dir) do
    path = Path.join(binaries_dir, "yt-dlp") |> Path.expand()

    if File.exists?(path) do
      path
    else
      Logger.info("yt-dlp not found at #{path}, downloading...")
      download_yt_dlp(binaries_dir)
      unless File.exists?(path), do: raise("Failed to download yt-dlp to #{path}")
      path
    end
  end

  defp download_yt_dlp(binaries_dir) do
    dir = Path.expand(binaries_dir)
    File.mkdir_p!(dir)
    dest = Path.join(dir, "yt-dlp")

    url =
      case {:os.type(), system_arch()} do
        {{:unix, :linux}, :x86_64} ->
          "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_linux"

        {{:unix, :linux}, :arm64} ->
          "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_linux_aarch64"

        {{:unix, :darwin}, _} ->
          "https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_macos"
      end

    Logger.info("Downloading yt-dlp from #{url}")

    case System.cmd("curl", ["-L", "--fail", "-o", dest, url], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> raise "Failed to download yt-dlp: #{output}"
    end
  end

  # ffmpeg: download from yt-dlp/FFmpeg-Builds (Linux only), fall back to system PATH on macOS

  defp ffmpeg_location_args(binaries_dir) do
    ffmpeg_path = Path.join(binaries_dir, "ffmpeg") |> Path.expand()

    cond do
      File.exists?(ffmpeg_path) ->
        [{"ffmpeg-location", prepare_executable(ffmpeg_path)}]

      :os.type() == {:unix, :linux} ->
        download_ffmpeg(binaries_dir)
        [{"ffmpeg-location", prepare_executable(ffmpeg_path)}]

      true ->
        # On macOS, yt-dlp/FFmpeg-Builds doesn't provide binaries.
        # Rely on system ffmpeg from PATH (e.g. homebrew).
        if System.find_executable("ffmpeg") do
          Logger.info("Using system ffmpeg from PATH")
          []
        else
          Logger.error("ffmpeg not found. Install it with: brew install ffmpeg")
          raise "ffmpeg not found. Install it with: brew install ffmpeg"
        end
    end
  end

  defp download_ffmpeg(binaries_dir) do
    dir = Path.expand(binaries_dir)
    File.mkdir_p!(dir)

    archive_name =
      case system_arch() do
        :x86_64 -> "ffmpeg-master-latest-linux64-gpl.tar.xz"
        :arm64 -> "ffmpeg-master-latest-linuxarm64-gpl.tar.xz"
      end

    url = "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/#{archive_name}"
    archive_path = Path.join(System.tmp_dir!(), "ffmpeg.tar.xz")

    Logger.info("Downloading ffmpeg from #{url}")

    case System.cmd("curl", ["-L", "--fail", "-o", archive_path, url],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {output, _} -> raise "Failed to download ffmpeg: #{output}"
    end

    extract_ffmpeg(archive_path, dir)
    File.rm(archive_path)
  end

  defp extract_ffmpeg(archive_path, target_dir) do
    tmp = Path.join(System.tmp_dir!(), "ffmpeg-extract-#{System.unique_integer([:positive])}")
    File.rm_rf(tmp)
    File.mkdir_p!(tmp)

    try do
      {_, 0} = System.cmd("tar", ["-xJf", archive_path, "-C", tmp], stderr_to_stdout: true)

      ffmpeg_src =
        Path.wildcard(Path.join([tmp, "**", "bin", "ffmpeg"]))
        |> List.first() ||
          raise "Could not find ffmpeg binary in extracted archive"

      File.cp!(ffmpeg_src, Path.join(target_dir, "ffmpeg"))
      Logger.info("ffmpeg downloaded successfully to #{target_dir}")
    after
      File.rm_rf(tmp)
    end
  end

  # Utilities

  defp system_arch do
    case :erlang.system_info(:system_architecture) |> to_string() do
      "aarch64" <> _ -> :arm64
      "arm" <> _ -> :arm64
      _ -> :x86_64
    end
  end

  # Nightly channel: YouTube extraction breaks faster than stable releases ship
  # (e.g. the android_vr client 403s that nightly fixed weeks before a stable release).
  defp update_yt_dlp(path) do
    case System.cmd(path, ["--update-to", "nightly"], stderr_to_stdout: true) do
      {output, 0} ->
        Logger.info("yt-dlp -U: #{String.trim(output)}")

      {output, status} ->
        Logger.warning("yt-dlp self-update failed (exit #{status}): #{String.trim(output)}")
    end
  end

  defp binaries_path do
    case :os.type() do
      {:unix, :darwin} -> "./binaries/mac/"
      {:unix, :linux} -> "./binaries/linux/"
    end
  end
end
