defmodule Torrex.Tracker.Pool do
  @moduledoc """
  Supervises HTTP and UDP tracker communications
  """

  use Supervisor

  @spec start_link(binary, port, port) :: Supervisor.on_start()
  def start_link(peer_id, tcp_port, udp_port) do
    Supervisor.start_link(__MODULE__, [peer_id, tcp_port, udp_port], name: __MODULE__)
  end

  @impl true
  def init([peer_id, tcp_port, udp_port]) do
    children = [
      worker(Torrex.Tracker.HTTP, [peer_id, tcp_port]),
      worker(Torrex.Tracker.UDP, [peer_id, tcp_port, udp_port])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
