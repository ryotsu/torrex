defmodule Torrex.Peer.Pool do
  use DynamicSupervisor

  require Logger

  alias Torrex.Peer.Worker, as: PeerWorker

  def start_link do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  def count_children(pid) do
    DynamicSupervisor.count_children(pid)
  end

  def get_children(pid) do
    DynamicSupervisor.which_children(pid)
  end

  def start_peer(pid, socket, control_pid, file_worker) do
    spec = {PeerWorker, [socket, control_pid, file_worker]}
    DynamicSupervisor.start_child(pid, spec)
  end

  def init([]) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
