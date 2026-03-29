defmodule Tonie.ThumbnailCache do
  @moduledoc """
  In-memory ETS cache for proxied thumbnail images.
  Fetches from Google with bounded concurrency to avoid rate limits.
  Entries expire after 7 days (thumbnails are essentially immutable).
  """
  use GenServer

  @table :thumbnail_cache
  @ttl_ms :timer.hours(24 * 7)
  @sweep_interval_ms :timer.hours(1)
  @max_concurrent 3
  @max_retries 2

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Returns `{:ok, content_type, binary}` or `{:error, reason}`.
  Fetches are deduped and bounded to #{@max_concurrent} concurrent upstream requests.
  """
  def fetch(url) when is_binary(url) do
    case :ets.lookup(@table, url) do
      [{^url, content_type, body, _inserted_at}] ->
        {:ok, content_type, body}

      [] ->
        ref = make_ref()
        GenServer.cast(__MODULE__, {:request, url, self(), ref})

        receive do
          {:thumb_result, ^ref, result} -> result
        after
          30_000 -> {:error, :timeout}
        end
    end
  end

  # --- Server ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, %{inflight: %{}, queue: :queue.new(), active: 0}}
  end

  @impl true
  def handle_cast({:request, url, pid, ref}, state) do
    # Check cache (may have been filled while message was in queue)
    case :ets.lookup(@table, url) do
      [{^url, content_type, body, _}] ->
        send(pid, {:thumb_result, ref, {:ok, content_type, body}})
        {:noreply, state}

      [] ->
        waiter = {pid, ref}

        case Map.get(state.inflight, url) do
          # Already in-flight or queued — piggyback
          waiters when is_list(waiters) ->
            {:noreply, put_in(state.inflight[url], [waiter | waiters])}

          nil ->
            state = put_in(state.inflight[url], [waiter])
            {:noreply, maybe_start_fetch(url, state)}
        end
    end
  end

  @impl true
  def handle_cast({:fetch_complete, url, result}, state) do
    case result do
      {:ok, content_type, body} ->
        :ets.insert(@table, {url, content_type, body, System.monotonic_time(:millisecond)})

      _ ->
        :ok
    end

    waiters =
      case Map.get(state.inflight, url) do
        {_task_pid, list} -> list
        list when is_list(list) -> list
        nil -> []
      end

    for {pid, ref} <- waiters do
      send(pid, {:thumb_result, ref, result})
    end

    state = %{state | inflight: Map.delete(state.inflight, url), active: state.active - 1}
    {:noreply, drain_queue(state)}
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

  # Task crash — notify waiters, free slot, drain queue
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case Enum.find(state.inflight, fn {_url, v} -> is_tuple(v) and elem(v, 0) == pid end) do
      {url, {_pid, waiters}} ->
        for {wpid, wref} <- waiters do
          send(wpid, {:thumb_result, wref, {:error, reason}})
        end

        state = %{state | inflight: Map.delete(state.inflight, url), active: state.active - 1}
        {:noreply, drain_queue(state)}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Internal ---

  defp maybe_start_fetch(url, state) do
    if state.active < @max_concurrent do
      start_task(url, state)
    else
      %{state | queue: :queue.in(url, state.queue)}
    end
  end

  defp drain_queue(state) do
    case :queue.out(state.queue) do
      {{:value, url}, new_queue} ->
        state = %{state | queue: new_queue}

        if Map.has_key?(state.inflight, url) do
          start_task(url, state)
        else
          # URL was already resolved (e.g. duplicate in queue) — skip
          drain_queue(state)
        end

      {:empty, _} ->
        state
    end
  end

  defp start_task(url, state) do
    pid =
      spawn(fn ->
        result = do_fetch_with_retry(url, 0)
        GenServer.cast(__MODULE__, {:fetch_complete, url, result})
      end)

    Process.monitor(pid)
    # Replace waiter list with {task_pid, waiters} to track task crashes
    waiters = Map.get(state.inflight, url, [])
    %{state | inflight: Map.put(state.inflight, url, {pid, waiters}), active: state.active + 1}
  end

  defp do_fetch_with_retry(url, attempt) do
    case do_fetch(url) do
      {:ok, _, _} = success ->
        success

      _error when attempt < @max_retries ->
        Process.sleep(1000 * (attempt + 1))
        do_fetch_with_retry(url, attempt + 1)

      error ->
        error
    end
  end

  defp do_fetch(url) do
    uri = URI.parse(url)

    if uri.scheme == "https" do
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
      {:error, :blocked_scheme}
    end
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end
end
