defmodule Tonie.ThumbnailCache do
  @moduledoc """
  In-memory ETS cache for proxied thumbnail images.
  Fetches from Google once, then serves from cache.
  Entries expire after 1 hour.
  """
  use GenServer

  @table :thumbnail_cache
  @ttl_ms :timer.hours(1)
  @sweep_interval_ms :timer.minutes(10)
  @allowed_hosts ["lh3.googleusercontent.com", "yt3.googleusercontent.com"]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns `{:ok, content_type, binary}` or `{:error, reason}`.
  """
  def fetch(url) when is_binary(url) do
    case :ets.lookup(@table, url) do
      [{^url, content_type, body, _inserted_at}] ->
        {:ok, content_type, body}

      [] ->
        GenServer.call(__MODULE__, {:fetch, url}, 15_000)
    end
  end

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:fetch, url}, _from, state) do
    # Double-check after acquiring the call (another request may have cached it)
    case :ets.lookup(@table, url) do
      [{^url, content_type, body, _}] ->
        {:reply, {:ok, content_type, body}, state}

      [] ->
        result = do_fetch(url)

        case result do
          {:ok, content_type, body} ->
            :ets.insert(@table, {url, content_type, body, System.monotonic_time(:millisecond)})
            {:reply, {:ok, content_type, body}, state}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)

    :ets.select_delete(@table, [
      {{:_, :_, :_, :"$1"}, [{:<, :"$1", now - @ttl_ms}], [true]}
    ])

    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp do_fetch(url) do
    uri = URI.parse(url)

    if uri.host in @allowed_hosts do
      case Req.get(url, headers: [{"user-agent", "Mozilla/5.0"}], receive_timeout: 10_000) do
        {:ok, %{status: 200, headers: headers, body: body}} when is_binary(body) ->
          content_type =
            case headers do
              %{"content-type" => [ct | _]} -> ct
              _ -> "image/jpeg"
            end

          {:ok, content_type, body}

        {:ok, %{status: status}} ->
          {:error, {:upstream_error, status}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :blocked_host}
    end
  end
end
