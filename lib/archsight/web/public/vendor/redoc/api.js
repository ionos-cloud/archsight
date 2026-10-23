// The API reference (/docs/api): ReDoc, vendored next to this file, renders the OpenAPI document of this server.
(function () {
  var back = document.getElementById('back')
  // back to where the reader came from, the start page when this page was opened directly
  back.addEventListener('click', function (event) {
    if (document.referrer.indexOf(location.origin) === 0 && history.length > 1) {
      event.preventDefault()
      history.back()
    }
  })

  if (!window.Redoc) {
    var error = document.getElementById('error')
    error.textContent = 'Failed to load ReDoc'
    error.hidden = false
    return
  }
  window.Redoc.init('/api/v1/openapi.yaml', {}, document.getElementById('redoc'))
})()
