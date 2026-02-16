#* Used for new device setup and then never used after.
#* @serializer unboxedJSON
#* @get /api/setup
function(req, res) {
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

  api_key <- uuid::UUIDgenerate()
  friendly_id <- paste0("TRMNL_", gsub(":", "", id))

  # Pick the first available image as the initial image_url
  images_dir <- "app/images"
  imgs <- list.files(images_dir, pattern = "\\.(png|bmp)$", ignore.case = TRUE)
  filename <- head(c(imgs, ""), 1)
  image_url <- paste0("/images/", filename)

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

#* Plot a histogram
#* @param ID Device ID
#* @get /api/display
function(ID) {}

#* Used by device firmware to log information about your device. Mostly used for debugging purposes.
#* @param ID Device ID
#* @param logs
#* @post /api/log
function(ID, logs) {}
