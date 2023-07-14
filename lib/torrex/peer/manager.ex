defmodule Torrex.Peer.Manager do
  use Supervisor

  @spec start_link(list) :: Supervisor.on_start()
  def start_link([info_hash, control_pid, file_worker]) do
    Supervisor.start_link(__MODULE__, [info_hash, control_pid, file_worker])
  end

  @spec start_peer_pool(pid) :: Supervisor.on_start_child()
  def start_peer_pool(pid) do
    child = {Torrex.Peer.Pool, []}

    Supervisor.start_child(pid, child)
  end

  @impl true
  def init([info_hash, control_pid, file_worker]) do
    children = [
      {Torrex.Peer.Control, [info_hash, control_pid, file_worker, self()]}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
