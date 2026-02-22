# Implementation Plan: TRMNL Server in R/Plumber

## Architecture

A single Docker container running an R/plumber API that:
- Serves the three TRMNL device endpoints (`/api/setup`, `/api/display`, `/api/log`)
- Accepts PNG uploads via a custom endpoint
- Lists all available PNGs
- Cycles through available images on each display request
- Stores images in a persistent volume

## Steps

### 1. Create the plumber API (`plumber.R`)

Implement these endpoints:

#### TRMNL Device Endpoints

- **`GET /api/setup`** — Read `ID` header (MAC address). Store it as the registered device. Return JSON with `status`, `api_key`, `friendly_id`, `image_url`, and `filename`. Generate a simple API key (e.g. a UUID via `uuid::UUIDgenerate()`). Persist the device registration to a small JSON or RDS file so it survives restarts.

- **`GET /api/display`** — Read `Access-Token` header to verify the device. Pick the next image from the `/images` directory (cycle through alphabetically, tracking the current index in a file or environment variable). Return JSON with `status: 0`, `image_url` pointing to the selected image, `filename`, `refresh_rate` (configurable, default 900 seconds), and `update_firmware: false`, `firmware_url: null`, `reset_firmware: false`.

- **`POST /api/log`** — Accept the log payload, write it to a log file or just print it. Return 200.

#### Custom Management Endpoints

- **`POST /upload`** — Accept any image file, then convert it with `convert_for_trmnl`. Save it to the `/images` directory, overwriting if a file with the same name exists. Alternativly accepts markdown strings, which are rendered with `render_md_bmp`

- **`GET /list`** — List all PNG/BMP files in the `/images` directory. Return as a JSON array with filenames and sizes.

- **`DELETE /delete`** — delete and image from `/images`.

#### Static File Serving

- **`GET /images/<filename>`** — Serve image files statically from the `/images` directory. Use `plumber::PlumberStatic` or a dedicated `@serializer contentType` endpoint to serve binary files with the correct MIME type.

### 2. Create a helper for image conversion (`convert.R`)

A small utility using the `magick` R package:
- Resize to 800x480 (fit within, pad if aspect ratio differs)
- Convert to grayscale
- Reduce to 1-bit monochrome (or 2-bit if preferred)
- Save as BMP3 or PNG
- Called automatically by the upload endpoint

### 3. Create the Dockerfile

```
FROM rocker/r-ver:4.4.0

RUN install2.r plumber uuid jsonlite magick

COPY plumber.R /app/plumber.R
COPY convert.R /app/convert.R

RUN mkdir -p /app/images /app/data

EXPOSE 8000

CMD ["R", "-e", "plumber::pr_run(plumber::pr('/app/plumber.R'), host='0.0.0.0', port=8000)"]
```

- Based on `rocker/r-ver` for a clean R environment
- `magick` R package needs `libmagick++-dev` — the rocker image may need an apt install step
- `/app/images` holds the served images
- `/app/data` holds device registration state and the cycle index

### 4. Create `docker-compose.yml`

```yaml
services:
  trmnl:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - ./images:/app/images
      - ./data:/app/data
    restart: unless-stopped
```

- Mount `./images` so you can also drop files in manually
- Mount `./data` to persist device registration across container restarts

### 5. Add a default welcome image

Create or include a simple default 800x480 BMP/PNG (e.g. "TRMNL Ready" text on white background) so the device has something to display immediately after setup. Can be generated in R using `magick`:

```r
library(magick)
img <- image_blank(800, 480, "white") |>
  image_annotate("TRMNL Ready", size = 60, gravity = "center", color = "black")
image_write(img, "images/welcome.bmp", format = "BMP3")
```

### 6. Test locally

1. `docker compose up --build`
2. Test setup: `curl -H "ID: AA:BB:CC:DD:EE:FF" http://localhost:8000/api/setup`
3. Test display: `curl -H "Access-Token: <key-from-setup>" -H "ID: <friendly-id>" http://localhost:8000/api/display`
4. Test upload: `curl -X POST -F "file=@myimage.png" http://localhost:8000/upload`
5. Test list: `curl http://localhost:8000/list`
6. Verify the image URL returned by `/api/display` is fetchable and renders correctly

### 7. Wire up the TRMNL device

Follow the README instructions to point the device at `http://<your-machine-ip>:8000`. Verify it picks up images and cycles through them.

## File Structure

```
trmnl/
  README.md
  plan.md
  Dockerfile
  docker-compose.yml
  plumber.R          # Main API
  convert.R          # Image conversion helper
  images/            # Served images (mounted volume)
    welcome.bmp      # Default image
  data/              # Persistent state (mounted volume)
    device.rds       # Registered device info
    index.rds        # Current cycle index
```

## R Package Dependencies

| Package | Purpose |
|---------|---------|
| plumber | HTTP API framework |
| jsonlite | JSON serialization |
| uuid | Generate API keys |
| magick | Image conversion (ImageMagick bindings) |

## Open Questions / Future Ideas

- **Authentication on management endpoints:** The `/upload` and `/list` endpoints are currently open. Consider adding a simple shared secret via header or query param if the server is exposed beyond localhost.
- **Cycling strategy:** Alphabetical round-robin is simplest. Could add random, weighted, or time-based scheduling later.
- **Multiple devices:** Current plan tracks one device. Could extend to support multiple with a device registry keyed by MAC address.
- **Script hooks:** The mounted `images/` volume means external scripts (cron jobs, R scripts, Python scripts) can drop images directly into the folder without using the upload endpoint.
