defmodule Torrex.UPnP do
  @moduledoc """
  Maps external port to internal port
  """

  use GenServer

  alias Torrex.XMLHelper

  @ssdp_addr "239.255.255.250"
  @ssdp_port 1900
  @ssdp_mx 2
  @ssdp_st "urn:schemas-upnp-org:device:InternetGatewayDevice:1"

  @duration 1800
  @timeout 300_000

  @spec start_link(integer) :: GenServer.on_start()
  def start_link(port) do
    GenServer.start_link(__MODULE__, port, name: __MODULE__)
  end

  def init(port) do
    {:ok, port, {:continue, :init}}
  end

  def handle_continue(:init, port) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    Process.send_after(self(), :remap, 0)
    {:noreply, {port, socket}}
  end

  def handle_info(:remap, {port, socket}) do
    case map_port(port, socket) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Process.send_after(self(), :remap, (@duration - 60) * 1000)

      _ ->
        Process.send_after(self(), :remap, @timeout)
    end

    {:noreply, {port, socket}}
  end

  @spec map_port(integer, port, integer) ::
          {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  defp map_port(port, socket, enable \\ 1) do
    router_url = get_router_url(socket)
    parsed_url = URI.parse(router_url)
    local_ip = get_local_ip()

    case get_wanip_path(router_url) do
      {:ok, wanip_path} ->
        service_url = %URI{parsed_url | path: wanip_path} |> URI.to_string()
        request_port_map(service_url, port, local_ip, enable)

      error ->
        error
    end
  end

  @spec request_port_map(String.t(), integer, String.t(), integer) ::
          {:ok, HTTPoison.Response.t()} | {:error, HTTPoison.Error.t()}
  defp request_port_map(service_url, port, ip, enable) do
    request = XMLHelper.build_mapping_request(port, ip, enable, @duration, "TCP")

    headers = [
      {"SOAPAction", "\"urn:schemas-upnp-org:service:WANIPConnection:1#AddPortMapping\""},
      {"Content-type", "text/html"}
    ]

    HTTPoison.post(service_url, request, headers)
  end

  @spec get_router_url(port) :: String.t()
  defp get_router_url(socket) do
    request = ssdp_request()
    :ok = :gen_udp.send(socket, String.to_charlist(@ssdp_addr), @ssdp_port, request)
    {:ok, {_addr, _port, data}} = :gen_udp.recv(socket, 0)
    matches = Regex.scan(~r/(?<name>[^:]+):? ?(?<value>.+)\r\n/, data)

    Enum.find_value(matches, fn [_, name, value] ->
      if name |> String.trim() |> String.downcase() == "location", do: value, else: false
    end)
  end

  @spec get_wanip_path(String.t()) :: {:ok, String.t()} | {:error, HTTPoison.Error.t()}
  defp get_wanip_path(router_url) do
    with {:ok, response} <- HTTPoison.get(router_url) do
      {:ok, XMLHelper.get_wanip_path(response.body)}
    end
  end

  @spec get_local_ip :: binary
  def get_local_ip do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    :ok = :gen_udp.connect(socket, {8, 8, 8, 8}, 80)
    {:ok, {ip, _port}} = :inet.sockname(socket)
    :ok = :gen_udp.close(socket)
    ip |> Tuple.to_list() |> Enum.join(".")
  end

  @spec ssdp_request :: binary
  defp ssdp_request do
    "M-SEARCH * HTTP/1.1\r\n" <>
      "HOST: #{@ssdp_addr}:#{@ssdp_port}\r\n" <>
      "MAN: \"ssdp:discover\"\r\n" <> "MX: #{@ssdp_mx}\r\n" <> "ST: #{@ssdp_st}\r\n\r\n"
  end
end
