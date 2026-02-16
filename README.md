# TRMNL Self-Hosted Server (R/Plumber)

A minimal self-hosted server for the [TRMNL](https://trmnl.com/) e-ink display, written in R using [plumber](https://www.rplumber.io/). Runs in Docker, serves BMP/PNG images to your device over your local network.

## Connecting Your TRMNL Device to a Custom Server

### 1. Enter Setup Mode

Hold the round button on the back of the device for 5+ seconds until it enters setup mode and broadcasts a WiFi network called **TRMNL**.

### 2. Connect to the Device

On your phone or laptop, connect to the **TRMNL** WiFi network. A captive portal should appear automatically.

### 3. Point to Your Custom Server

In the captive portal, navigate to:

**Advanced > Custom Server > Yes**

Enter your server's local IP address and port, e.g.:

```
http://192.168.1.50:8000
```

**Important:** Do NOT include a trailing slash.

### 4. Connect to Your WiFi

Select your home/office WiFi network, enter the password, and click **Connect**. The device will now register with your self-hosted server and start requesting images from it.

## API Overview

The TRMNL device expects three endpoints:

### `GET /api/setup`

Called once when the device first connects. The device sends its MAC address in the `ID` header.

**Response (200):**
```json
{
  "status": 200,
  "api_key": "some-api-key",
  "friendly_id": "ABC123",
  "image_url": "http://192.168.1.50:8000/images/welcome.bmp",
  "filename": "welcome"
}
```

### `GET /api/display`

Called periodically to fetch the current screen image. Headers include `ID`, `Access-Token`, `Refresh-Rate`, `Battery-Voltage`, `FW-Version`, and `RSSI`.

**Response:**
```json
{
  "status": 0,
  "image_url": "http://192.168.1.50:8000/images/current.bmp",
  "filename": "current",
  "update_firmware": false,
  "firmware_url": null,
  "refresh_rate": 900,
  "reset_firmware": false
}
```

### `POST /api/log`

Receives device logs. Can simply return 200.

## Image Requirements

- **Resolution:** 800x480 pixels
- **Format:** BMP (BMP3) or PNG
- **Color depth:** 1-bit monochrome (black & white), or 2-bit grayscale (4 shades, requires firmware >= 1.6.0)

To convert an image with ImageMagick:

```bash
# 1-bit BMP (most compatible)
convert input.png -resize 800x480 -gravity center -extent 800x480 -colorspace Gray -monochrome BMP3:output.bmp

# 1-bit PNG
convert input.png -resize 800x480 -gravity center -extent 800x480 -colorspace Gray -monochrome output.png
```

## References

- [TRMNL BYOS Documentation](https://docs.trmnl.com/go/diy/byos)
- [TRMNL Firmware / API Spec](https://github.com/usetrmnl/firmware)
- [ImageMagick Guide](https://docs.trmnl.com/go/diy/imagemagick-guide)
- [Connect Device to Custom Server](https://help.trmnl.com/en/articles/12263392-connect-your-device-to-terminus-byos)
- [BYOS Node Lite (reference implementation)](https://github.com/usetrmnl/byos_node_lite)
