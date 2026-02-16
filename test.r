### start server
rx <- callr::r_bg(function() {
  plumber::pr("serve.r") |>
    plumber::pr_run(port = 8000)
})
rx$is_alive()

### test
library(httr2)
# Should give 400 Bad Request
request("http://localhost:8000/api/setup") |>
  req_error(body = \(resp) resp_body_string(resp)) |>
  req_perform()

# Should work and produce output similar to
#> {
#>   "api_key": "<redacted>",
#>   "friendly_id": "ABC123",
#>   "image_url": "https://localhost:2443/assets/setup.bmp",
#>   "message": "Welcome to TRMNL BYOS"
#> }
request("http://localhost:8000/api/setup") |>
  req_error(body = \(resp) resp_body_string(resp)) |>
  req_headers(
    ID = "1",
    `Content-Type` = "application/json",
  ) |>
  req_perform() |>
  resp_body_string()


rx$kill()
