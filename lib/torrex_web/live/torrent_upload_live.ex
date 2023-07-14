defmodule TorrexWeb.TorrentUploadLive do
  use TorrexWeb, :html

  use Phoenix.LiveView

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    socket =
      allow_upload(socket, :torrent,
        accept: [".torrent"],
        max_entries: 1,
        progress: &handle_progress/3,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :torrent, ref)}
  end

  @impl Phoenix.LiveView
  def handle_event(_msg, _params, socket) do
    {:noreply, socket}
  end

  defp handle_progress(:torrent, entry, socket) do
    if entry.done? do
      torrent =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          dest_folder = Path.join([:code.priv_dir(:torrex), "static", "torrents"])

          if not File.exists?(dest_folder) do
            File.mkdir_p(dest_folder)
          end

          dest = Path.join([dest_folder, Path.basename(path)])
          File.cp!(path, dest)

          file = dest |> File.stat!() |> Map.merge(%{path: dest})

          {:ok, file}
        end)

      case Torrex.add_torrent(torrent.path) do
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Error while adding torrent: #{reason}")}

        _ ->
          {:noreply, put_flash(socket, :info, "Torrent File Added")}
      end
    else
      {:noreply, socket}
    end
  end

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:too_many_files), do: "You have selected too many files"
  defp error_to_string(:not_accepted), do: "You have selected an unacceptable file type"
end
