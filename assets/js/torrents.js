let add_torrent_component = (torrent) => {
  let card = document.createElement("div")
  card.classList.add("card", "border-dark", "mb-2")
  card.id = torrent.info_hash

  let card_body = document.createElement("div")
  card_body.classList.add("card-body")

  let card_title = document.createElement("div")
  card_title.classList.add("card-title")

  let name = document.createElement("div")
  name.classList.add("mr-auto")
  let text = document.createTextNode(torrent.name)
  name.appendChild(text)

  let info = document.createElement("small")
  info.classList.add("text-muted")

  let on_disk = document.createElement("span")
  on_disk.classList.add("on-disk")
  on_disk.appendChild(document.createTextNode(format_data(torrent.on_disk)))
  info.appendChild(on_disk)

  let size = document.createElement("span")
  size.appendChild(document.createTextNode(` / ${format_data(torrent.size)} -- Downloading at `))
  info.appendChild(size)

  let download = document.createElement("span")
  download.classList.add("download-speed")
  download.appendChild(document.createTextNode(`${format_data(torrent.download_speed)}/s`))
  info.appendChild(download)

  card_title.appendChild(name)
  card_title.appendChild(info)

  let progress_container = document.createElement("div")
  progress_container.classList.add("progress")

  let progress = document.createElement("div")
  progress.classList.add("progress-bar")
  if (torrent.on_disk == torrent.size) progress.classList.add("bg-success")
  progress.setAttribute("role", "progressbar")
  progress.setAttribute("aria-valuenow", torrent.on_disk)
  progress.setAttribute("aria-valuemin", 0)
  progress.setAttribute("aria-valuemax", torrent.size)
  progress.style.width = `${(torrent.on_disk / torrent.size) * 100}%`
  progress.appendChild(document.createTextNode(`${(torrent.on_disk / torrent.size * 100).toFixed(2)}%`))

  progress_container.appendChild(progress)

  card_body.appendChild(card_title)
  card_body.appendChild(progress_container)

  card.appendChild(card_body)

  return card
}

let format_data = (size) => {
  let count = 0

  while (size > 1024) {
    size = size / 1024
    count += 1
  }

  size = size.toFixed(2)
  let specifier = ["", "K", "M", "G", "T"][count]

  return `${size} ${specifier}B`
}

let add_torrent = (file, csrf_token) => {
  let data = new FormData()
  data.append("torrent", file)
  data.append("_csrf_token", csrf_token)

  console.log(csrf_token);
  fetch("/add", {
    method: "POST",
    body: data
  }).then(
    response => response.json()
  ).then(resp => {
    // let csrf = document.getElementById("csrf-token")
    // csrf.value = resp.token
    console.log("Status: ", resp.success)
  }).catch(
    error => console.log(error)
  )
}



export { add_torrent_component, format_data, add_torrent }
