defmodule Tonie.WorkerTest do
  use ExUnit.Case, async: true

  import Tonie.Worker, only: [error_summary: 1]

  test "extracts ERROR lines from yt-dlp output" do
    output = """
    [youtube] Extracting URL: https://music.youtube.com/watch?v=abc
    ERROR: unable to download video data: HTTP Error 403: Forbidden
    [download] Downloading item 2 of 12
    ERROR: unable to download video data: HTTP Error 403: Forbidden
    """

    assert error_summary(output) ==
             "ERROR: unable to download video data: HTTP Error 403: Forbidden"
  end

  test "falls back to last lines when no ERROR lines present" do
    assert error_summary("line1\nline2\nline3\nline4\n") == "line2\nline3\nline4"
  end

  test "inspects non-binary reasons" do
    assert error_summary(:timeout) == ":timeout"
  end
end
