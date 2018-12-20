defmodule Torrex.Torrent.Supervisor do
  use Supervisor

  @spec start_link(binary, String.t()) :: Supervisor.on_start()
  def start_link(info_hash, name) do
    hex = info_hash |> Base.encode16() |> binary_part(0, 5)
    name = (name <> "-#{hex}") |> String.to_atom()
    Supervisor.start_link(__MODULE__, info_hash, name: name)
  end

  @spec start_peer_manager(pid, binary, pid, pid) :: Supervisor.on_start_child()
  def start_peer_manager(pid, info_hash, control_pid, file_worker) do
    child =
      supervisor(Torrex.Peer.Manager, [info_hash, control_pid, file_worker], restart: :transient)

    Supervisor.start_child(pid, child)
  end

  @spec add_tracker(pid, binary, pid) :: Supervisor.on_start_child()
  def add_tracker(pid, info_hash, control_pid) do
    child = worker(Torrex.Tracker, [info_hash, control_pid], restart: :transient)

    Supervisor.start_child(pid, child)
  end

  def start_file_worker(pid, info_hash, bitfield, control_pid) do
    child = worker(Torrex.FileIO.Worker, [info_hash, bitfield, control_pid], restart: :transient)

    Supervisor.start_child(pid, child)
  end

  def init(info_hash) do
    children = [
      worker(Torrex.Torrent.Control, [self(), info_hash], restart: :transient)
    ]

    supervise(children, strategy: :one_for_all)
  end
end
