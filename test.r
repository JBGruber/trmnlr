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
reg <- request("http://localhost:8000/api/setup") |>
  req_error(body = \(resp) resp_body_string(resp)) |>
  req_headers(
    ID = "1",
    `Content-Type` = "application/json",
  ) |>
  req_perform() |>
  resp_body_json()
reg

# test logging
request("http://localhost:8000/api/log") |>
  req_method("POST") |>
  req_headers(ID = "1") |>
  req_body_json(
    data = list(
      logs = list(
        id = 667L,
        message = "An API test.",
        wifi_status = "connected",
        created_at = 1742022124L,
        sleep_duration = 31L,
        refresh_rate = 30L,
        free_heap_size = 160656L,
        max_alloc_size = 180000L,
        source_path = "src/bl.cpp",
        wake_reason = "timer",
        firmware_version = "1.5.2",
        retry = 1L,
        battery_voltage = 4.772,
        source_line = 597L,
        special_function = "none",
        wifi_signal = -54L
      )
    )
  ) |>
  req_perform()
readr::read_csv("app/data/device_log.csv")

# test display
request("http://localhost:8000/api/display") |>
  req_headers(ID = "1", ACCESS_TOKEN = reg$api_key) |>
  req_perform() |>
  resp_body_string()

rx$kill()
