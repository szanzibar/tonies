defmodule TonieWeb.ComponentHelpers do
  @moduledoc """
  Shared helpers used across all component modules.
  """

  def thumb(url) when is_binary(url) do
    "/thumb/" <> Base.url_encode64(url, padding: false)
  end

  def thumb(_), do: nil
end
