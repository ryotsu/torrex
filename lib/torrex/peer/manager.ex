defmodule Torrex.Peer.Manager do
  use Supervisor

  @spec start_link(binary, pid, pid) :: Supervisor.on_start()
  def start_link(info_hash, control_pid, file_worker) do
    Supervisor.start_link(__MODULE__, [info_hash, control_pid, file_worker])
  end

  def start_peer_pool(pid) do
    child = supervisor(Torrex.Peer.Pool, [])

    Supervisor.start_child(pid, child)
  end

  def init([info_hash, control_pid, file_worker]) do
    children = [
      worker(Torrex.Peer.Control, [info_hash, control_pid, file_worker, self()])
    ]

    supervise(children, strategy: :one_for_all)
  end
end
