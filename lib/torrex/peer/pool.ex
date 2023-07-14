defmodule Torrex.Peer.Pool do
  use DynamicSupervisor

  require Logger

  alias Torrex.Peer.Worker, as: PeerWorker

  @spec start_link(list) :: Supervisor.on_start()
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  @spec count_children(pid) :: map
  def count_children(pid) do
    DynamicSupervisor.count_children(pid)
  end

  @spec get_children(pid) :: list
  def get_children(pid) do
    DynamicSupervisor.which_children(pid)
  end

  @spec start_peer(pid, port, pid, pid, binary) :: DynamicSupervisor.on_start_child()
  def start_peer(pid, socket, control_pid, file_worker, info_hash) do
    spec = {PeerWorker, [socket, control_pid, file_worker, info_hash]}
    DynamicSupervisor.start_child(pid, spec)
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
