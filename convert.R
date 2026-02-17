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
  img <- magick::image_resize(img, "800x480!")
  img <- magick::image_convert(img, type = "Bilevel")
  magick::image_write(img, output, format = "BMP3")

  invisible(output)
}
