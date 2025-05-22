defmodule Tonie.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TonieWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:tonie, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Tonie.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Tonie.Finch},
      # Start a worker by calling: Tonie.Worker.start_link(arg)
      # {Tonie.Worker, arg},
      # Start to serve requests, typically the last entry
      TonieWeb.Endpoint,
      Tonie.Worker
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Tonie.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TonieWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
