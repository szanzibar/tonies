defmodule TonieWeb.ThumbnailController do
  use TonieWeb, :controller

  alias Tonie.ThumbnailCache

  @doc """
  Proxies and caches thumbnail images.

  Expects a base64url-encoded original URL as the `url` param.
  Returns the image with aggressive browser caching headers.
  """
  def show(conn, %{"url" => encoded_url}) do
    with {:ok, url} <- Base.url_decode64(encoded_url, padding: false),
         {:ok, content_type, body} <- ThumbnailCache.fetch(url) do
      conn
      |> put_resp_content_type(content_type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> send_resp(200, body)
    else
      _ ->
        send_resp(conn, 404, "")
    end
  end
end
