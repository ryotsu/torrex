defmodule Torrex do
  @moduledoc """
  Torrex keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  defdelegate add_torrent(path), to: Torrex.TorrentTable
end
