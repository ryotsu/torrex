defmodule Torrex.Tracker.Pool do
  @moduledoc """
  Supervises HTTP and UDP tracker communications
  """

  use Supervisor

  @spec start_link(list) :: Supervisor.on_start()
  def start_link([peer_id, tcp_port, udp_port]) do
    Supervisor.start_link(__MODULE__, [peer_id, tcp_port, udp_port], name: __MODULE__)
  end

  @impl true
  def init([peer_id, tcp_port, udp_port]) do
    children = [
      {Torrex.Tracker.HTTP, [peer_id, tcp_port]},
      {Torrex.Tracker.UDP, [peer_id, tcp_port, udp_port]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
