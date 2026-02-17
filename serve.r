#* Used for new device setup and then never used after.
#* @serializer unboxedJSON
#* @get /api/setup
function(req, res) {
  cache_req(req, "setup")
  id <- req$HTTP_ID
  if (is.null(id) || id == "") {
    res$status <- 400L
    return(list(error = "Missing ID header"))
  }
  device_file <- "app/data/device.rds"
  dir.create(dirname(device_file), recursive = TRUE, showWarnings = FALSE)

  # Return existing registration if device already registered
  if (file.exists(device_file)) {
    device <- readRDS(device_file)
    if (device$mac == id) {
      return(device$response)
    }
  }

  api_key <- paste0(
    sample(c(LETTERS, letters, 0:9), size = 22, replace = TRUE),
    collapse = ""
  )
  friendly_id <- paste0("TRMNL_", gsub(":", "", id))

  # Pick the first available image as the initial image_url
  images_dir <- "app/images"
  imgs <- list.files(images_dir, pattern = "\\.(png|bmp)$", ignore.case = TRUE)
  filename <- head(c(imgs, ""), 1)
  base_url <- paste0("http://", req$HTTP_HOST)
  image_url <- paste0(base_url, "/images/", filename)

  response <- list(
    api_key = api_key,
    friendly_id = friendly_id,
    image_url = image_url,
    filename = filename
  )

  # Persist device registration
  saveRDS(
    list(
      mac = id,
      api_key = api_key,
      friendly_id = friendly_id,
      response = response
    ),
    device_file
  )

  return(response)
}


#* Returns the next image for the device to display, cycling through available images.
#* @serializer unboxedJSON
#* @get /api/display
function(req, res) {
  cache_req(req, "display")
  # Verify device via Access-Token header
  device_file <- "app/data/device.rds"
  device <- try(readRDS(device_file))
  if (methods::is(device, "try-error")) {
    res$status <- 401L
    return(list(error = "No device registered. Call /api/setup first."))
  }
  # turn off token validation
  # token <- req$HTTP_ACCESS_TOKEN
  # if (is.null(token) || token != device$api_key) {
  #   res$status <- 401L
  #   return(list(error = "Invalid Access-Token"))
  # }

  # List available images
  images_dir <- "app/images"
  files <- list.files(images_dir, pattern = "\\.(png|bmp)$", ignore.case = TRUE)
  if (length(files) == 0) {
    return(list(
      status = 0,
      image_url = "",
      filename = "",
      refresh_rate = 900,
      update_firmware = FALSE,
      firmware_url = NULL,
      reset_firmware = FALSE
    ))
  }

  # Cycle through images using a persisted index
  index_file <- "app/data/index.rds"
  idx <- if (file.exists(index_file)) readRDS(index_file) else 0L
  idx <- (idx %% length(files)) + 1L
  saveRDS(idx, index_file)

  filename <- files[idx]
  base_url <- paste0("http://", req$HTTP_HOST)
  image_url <- paste0(base_url, "/images/", filename)

  return(list(
    status = 0,
    image_url = image_url,
    filename = filename,
    refresh_rate = 900,
    update_firmware = FALSE,
    firmware_url = NULL,
    reset_firmware = FALSE
  ))
}


#* Used by device firmware to log information about your device. Mostly used for debugging purposes.
#* @serializer unboxedJSON
#* @post /api/log
function(req, res) {
  cache_req(req, "log")
  log_file <- "app/data/device_log.csv"
  dir.create(dirname(log_file), recursive = TRUE, showWarnings = FALSE)
  logs <- jsonlite::fromJSON(req$postBody)
  write.table(
    x = logs$logs,
    file = log_file,
    append = file.exists(log_file),
    quote = TRUE,
    sep = ",",
    eol = "\n",
    na = "NA",
    dec = ".",
    row.names = FALSE,
    col.names = !file.exists(log_file),
    qmethod = "escape",
    fileEncoding = "UTF-8"
  )

  res$status <- 204L
  return()
}


#* Serve an image file from the images directory.
#* @param filename The image filename
#* @serializer contentType list(type="application/octet-stream")
#* @get /images/<filename>
function(filename, res) {
  path <- file.path("app/images", filename)
  if (!file.exists(path)) {
    res$status <- 404L
    res$serializer <- plumber::serializer_unboxed_json()
    return(list(error = "Image not found"))
  }

  ext <- tolower(tools::file_ext(filename))
  mime <- switch(
    ext,
    png = "image/png",
    bmp = "image/bmp",
    "application/octet-stream"
  )
  res$setHeader("Content-Type", mime)
  readBin(path, "raw", file.info(path)$size)
}


cache_req <- function(req, method) {
  req_path <- paste0("app/cache/", method, "_last_req.rds")
  dir.create(dirname(req_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(req, req_path)
}
