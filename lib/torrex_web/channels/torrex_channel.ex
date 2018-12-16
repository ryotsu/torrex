defmodule TorrexWeb.TorrexChannel do
  use Phoenix.Channel

  require Logger

  def join("torrex:notifications", _message, socket) do
    torrents = Torrex.TorrentTable.subscribe()
    {payload, socket} = encode_info_hash(torrents, socket)
    {:ok, payload, socket}
  end

  def join("torrex:" <> _topic, _params, _socket) do
    {:error, %{reason: "unautorized"}}
  end

  def encode_info_hash(message, %{assigns: %{hash_lookup: lookup}} = socket) do
    {payload, hash_lookup} =
      Enum.reduce(message, {%{}, lookup}, fn {info_hash, value}, {acc, lookup} ->
        case Map.fetch(lookup, info_hash) do
          {:ok, encoded} ->
            {Map.put(acc, encoded, value), lookup}

          :error ->
            encoded = Base.encode16(info_hash)
            lookup = lookup |> Map.put(info_hash, encoded) |> Map.put(encoded, info_hash)
            {Map.put(acc, encoded, value), lookup}
        end
      end)

    socket = assign(socket, :hash_lookup, hash_lookup)

    {payload, socket}
  end

  def encode_info_hash(message, socket) do
    socket = assign(socket, :hash_lookup, %{})
    encode_info_hash(message, socket)
  end

  def handle_info({:update, speeds}, socket) do
    {payload, socket} = encode_info_hash(speeds, socket)
    push(socket, "update", payload)
    {:noreply, socket}
  end

  def handle_info({:saved, size}, socket) do
    {payload, socket} = encode_info_hash(size, socket)
    push(socket, "saved", payload)
    {:noreply, socket}
  end

  def handle_info({:left, size}, socket) do
    {payload, socket} = encode_info_hash(size, socket)
    push(socket, "left", payload)
    {:noreply, socket}
  end

  def handle_info({:added, torrent}, socket) do
    {payload, socket} = encode_info_hash(torrent, socket)
    push(socket, "added", payload)
    {:noreply, socket}
  end

  def handle_info(msg, socket) do
    IO.inspect(msg)
    {:noreply, socket}
  end
end
