defmodule Torrex.XMLHelper do
  @moduledoc """
  Utility for parsing XML
  """

  require Record

  Record.defrecord(:xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))
  Record.defrecord(:xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl"))

  @spec get_wanip_path(String.t()) :: String.t()
  def get_wanip_path(response) do
    response
    |> scan_text()
    |> parse_xml
  end

  @spec build_mapping_request(integer, String.t(), integer, integer, String.t()) :: String.t()
  def build_mapping_request(port, ip, enable, duration, protocol \\ "TCP") do
    '<?xml version="1.0" ?>
    <s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
      <s:Body>
        <u:AddPortMapping xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:1">
          <NewRemoteHost></NewRemoteHost>
          <NewExternalPort>#{port}</NewExternalPort>
          <NewProtocol>#{protocol}</NewProtocol>
          <NewInternalPort>#{port}</NewInternalPort>
          <NewInternalClient>#{ip}</NewInternalClient>
          <NewEnabled>#{enable}</NewEnabled>
          <NewPortMappingDescription>Torrex</NewPortMappingDescription>
          <NewLeaseDuration>#{duration}</NewLeaseDuration>
        </u:AddPortMapping>
      </s:Body>
    </s:Envelope>'
    |> to_string()
  end

  @spec scan_text(String.t()) :: term
  defp scan_text(text) do
    text
    |> String.to_charlist()
    |> :xmerl_scan.string()
  end

  @spec parse_xml({term, term}) :: String.t()
  defp parse_xml({xml, _}) do
    services = :xmerl_xpath.string('//serviceList/service', xml)

    Enum.find_value(services, fn service ->
      [service_type] = :xmerl_xpath.string('./serviceType', service)
      text = inner_text(service_type)

      if check_support(text) do
        [control_url] = :xmerl_xpath.string('./controlURL', service)
        inner_text(control_url)
      else
        false
      end
    end)
  end

  @spec check_support(String.t()) :: boolean
  defp check_support(text) do
    ["WANIPConnection", "WANPPPConnection"]
    |> Enum.map(&String.contains?(text, &1))
    |> Enum.any?()
  end

  @spec inner_text(term) :: String.t()
  defp inner_text(element) do
    [content] = xmlElement(element, :content)
    value = xmlText(content, :value)
    to_string(value)
  end
end
