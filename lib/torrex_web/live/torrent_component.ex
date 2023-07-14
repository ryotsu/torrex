defmodule TorrexWeb.TorrentComponent do
  import TorrexWeb.CoreComponents, [:icon]

  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 w-full mx-auto bg-white rounded-xl shadow-lg flex flex-col items-stretch space-y-4">
      <div class="flex space-x-4">
        <div class="shrink-0">
          <.icon name="hero-arrow-down-circle" class="h-10 w-10" />
        </div>
        <div>
          <div class="text-xl font-medium text-black"><%= @name %></div>
          <p class="text-slate-500 text-sm">
            <%= format_size(@size - @left) %>/<%= format_size(@size) %> - <%= format_size(
              @download_speed
            ) %>/s
          </p>
        </div>
      </div>
      <div class="w-full bg-gray-200 rounded-full h-2.5 dark:bg-gray-700">
        <%= if @left != 0 do %>
          <div class={"bg-blue-600 h-2.5 rounded-full w-[#{div((@size - @left) * 100,  @size)}%]"}>
          </div>
        <% else %>
          <div class={"bg-green-600 h-2.5 rounded-full w-[#{div((@size - @left) * 100,  @size)}%]"}>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def update(%{saved: size}, socket) do
    socket = assign(socket, left: socket.assigns.left - size)
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp format_size(size, count \\ 0)

  defp format_size(size, count) when size < 1024 do
    size = :erlang.float_to_binary(size / 1, decimals: 2)
    specifier = Enum.at(["", "K", "M", "G", "T"], count)

    "#{size} #{specifier}B"
  end

  defp format_size(size, count) do
    format_size(size / 1024, count + 1)
  end
end
