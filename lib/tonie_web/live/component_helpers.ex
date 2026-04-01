defmodule TonieWeb.ComponentHelpers do
  @moduledoc """
  Shared helpers used across all component modules.
  """

  def thumb(url) when is_binary(url) do
    url = String.trim(url)

    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        "/thumb/" <> Base.url_encode64(url, padding: false)

      _ ->
        nil
    end
  end

  def thumb(_), do: nil
end
