// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
// import {Socket} from "phoenix"
// import {LiveSocket} from "phoenix_live_view"
// import topbar from "../vendor/topbar"

// let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
// let liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: csrfToken}})

// Show progress bar on live navigation and form submits
// topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
// window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
// window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
// liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
// window.liveSocket = liveSocket

// Import local files
//
// Local files can be imported directly using relative paths, for example:
import socket from "./socket"
import { add_torrent_component, format_data } from "./torrents"
import "./add_torrent"

// Now that you are connected, you can join channels with a topic:
let channel = socket.channel("torrex:notifications", {})

let state = {}

channel.join()
  .receive("ok", resp => { init_torrents(resp) })
  .receive("error", resp => { console.log("Unable to join", resp) })

channel.on("update", speeds => {
  Object.keys(speeds).forEach(info_hash => {
    let torrent = Object.assign({}, state[info_hash], { "download_speed": speeds[info_hash] })
    state[info_hash] = torrent

    update_speed(info_hash, speeds[info_hash])
  })
})

channel.on("saved", size => {
  Object.keys(size).forEach(info_hash => {
    let t = state[info_hash]
    let torrent = Object.assign({}, t, {
      "on_disk": t.on_disk + size[info_hash],
      "left": t.left - size[info_hash]
    })
    state[info_hash] = torrent

    update_size(info_hash, torrent.on_disk, torrent.size)
  })
})

channel.on("left", size => {
  Object.keys(size).forEach(info_hash => {
    let t = state[info_hash]
    let torrent = Object.assign({}, t, {
      "on_disk": t.size - size[info_hash],
      "left": size[info_hash]
    })
    state[info_hash] = torrent

    update_size(info_hash, torrent.on_disk, torrent.size)
  })
})

channel.on("added", torrents => {
  init_torrents(torrents)
})

let init_torrents = (torrents) => {
  let container = document.getElementById("torrents")
  Object.keys(torrents).map(info_hash => {
    let t = torrents[info_hash]
    let torrent = Object.assign({}, t, {
      "on_disk": t.size - t.left,
      "info_hash": info_hash
    })

    let node = add_torrent_component(torrent)
    container.appendChild(node)
    state[info_hash] = torrent
  })
}

let update_speed = (info_hash, download_speed) => {
  let elem = document.getElementById(info_hash).getElementsByClassName("download-speed")[0]
  elem.textContent = `${format_data(download_speed)}/s`
}

let update_size = (info_hash, on_disk, size) => {
  let card = document.getElementById(info_hash)
  card.getElementsByClassName("on-disk")[0].textContent = `${format_data(on_disk)}`
  let progress = card.getElementsByClassName("progress-bar")[0]
  if (on_disk == size) progress.classList.add("bg-success")
  progress.setAttribute("aria-valuenow", size)
  progress.style.width = `${(on_disk / size) * 100}%`
  progress.textContent = `${((on_disk / size) * 100).toFixed(2)}%`
}
