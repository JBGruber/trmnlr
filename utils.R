#' Convert an image to TRMNL-compatible format (800x480 1-bit monochrome BMP).
#'
#' @param input Path to the source image.
#' @param output Path for the converted BMP. Defaults to same name with .bmp extension
#'   in the same directory.
#' @return The output path (invisibly).
convert_for_trmnl <- function(input, output = NULL) {
  if (is.null(output)) {
    output <- sub("\\.[^.]+$", ".bmp", input)
  }

  img <- magick::image_read(input)
  img <- magick::image_resize(img, "800x480")
  img <- magick::image_extent(
    img,
    "800x480",
    gravity = "center",
    color = "white"
  )
  img <- magick::image_quantize(
    img,
    max = 2,
    colorspace = "gray",
    dither = TRUE
  )
  img <- magick::image_convert(img, type = "Bilevel")
  magick::image_write(img, output, format = "BMP3")

  invisible(output)
}


# Example usage:
if (FALSE) {
  convert_for_trmnl(
    "https://www.r-project.org/logo/Rlogo.svg",
    output = "app/images/r.bmp"
  )
}


#' Render Markdown text onto an 800x480 BMP using marquee + grid.
#'
#' @param md Markdown string to render.
#' @param output Output file path.
#' @param style A `marquee::classic_style()` or custom style. Defaults to a
#'   mono-font style suited for the TRMNL e-ink display.
#' @return The output path (invisibly).
render_md_bmp <- function(
  md,
  output = "app/images/text.bmp",
  style = list(
    body_font = "mono",
    header_font = "mono",
    base_size = 18
  )
) {
  tmp <- tempfile(fileext = ".bmp")
  bmp(tmp, width = 800, height = 480, bg = "white", type = "cairo")
  grid::grid.newpage()

  style <- do.call(marquee::classic_style, style)

  marquee::marquee_grob(
    md,
    style = style,
    x = grid::unit(0.03, "npc"),
    y = grid::unit(0.97, "npc"),
    hjust = 0,
    vjust = 1,
    width = grid::unit(0.94, "npc")
  ) |>
    grid::grid.draw()
  dev.off()

  convert_for_trmnl(tmp, output)

  invisible(output)
}

# Example usage:
if (FALSE) {
  render_md_bmp(
    md = "# Monday
- Work:
    - [ ] E-Mails
    - [ ] Admin
    - [ ] Science!
- Cleaning:
    - [ ] Cooking
    - [ ] Cleaning kitchen",
    output = "app/images/monday.bmp"
  )
}
