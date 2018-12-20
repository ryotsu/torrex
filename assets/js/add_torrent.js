let add_torrent = (file, csrf_token) => {
  let data = new FormData()
  data.append("torrent", file)
  data.append("_csrf_token", csrf_token)

  fetch("/add", {
    method: "POST",
    body: data
  }).then(
    response => response.json()
  ).then(resp => {
    let csrf = document.getElementById("csrf-token")
    csrf.value = resp.token
    console.log("Status: ", resp.success)
  }).catch(
    error => console.log(error)
  )
}


let file_input = document.getElementById("add-torrent")
let csrf = document.getElementById("csrf-token")
let on_file_select = () => add_torrent(file_input.files[0], csrf.value)

file_input.addEventListener("change", on_file_select, false)
