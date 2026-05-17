# skills/calendar.r
# Generates an 800x480 monochrome BMP showing current month calendar (left 2/3)
# and tasks + upcoming events (right 1/3) for the TRMNL e-ink display.

suppressPackageStartupMessages({
  library(lubridate)
  library(ggplot2)
  library(grid)
  library(httr2)
  source("utils.R")
})

`%||%` <- function(x, y) if (!is.null(x)) x else y

# ── Windows TZ → IANA name lookup ────────────────────────────────────────────

.WIN_TZ <- c(
  "W. Europe Standard Time" = "Europe/Berlin",
  "Central Europe Standard Time" = "Europe/Prague",
  "Romance Standard Time" = "Europe/Paris",
  "GMT Standard Time" = "Europe/London",
  "UTC" = "UTC",
  "Eastern Standard Time" = "America/New_York",
  "Central Standard Time" = "America/Chicago",
  "Mountain Standard Time" = "America/Denver",
  "Pacific Standard Time" = "America/Los_Angeles",
  "Eastern Europe Standard Time" = "Europe/Bucharest",
  "FLE Standard Time" = "Europe/Helsinki",
  "GTB Standard Time" = "Europe/Athens",
  "Tokyo Standard Time" = "Asia/Tokyo",
  "China Standard Time" = "Asia/Shanghai",
  "India Standard Time" = "Asia/Kolkata",
  "AUS Eastern Standard Time" = "Australia/Sydney"
)

# ICS day abbreviations → ISO weekday number (Mon=1 ... Sun=7, lubridate week_start=1)
.ICS_WDAY <- c(MO = 1L, TU = 2L, WE = 3L, TH = 4L, FR = 5L, SA = 6L, SU = 7L)

# ── ICS parsing ───────────────────────────────────────────────────────────────

.resolve_tz <- function(tz_name) {
  if (is.null(tz_name) || is.na(tz_name) || !nzchar(tz_name)) {
    return("UTC")
  }
  if (tz_name %in% names(.WIN_TZ)) {
    return(unname(.WIN_TZ[tz_name]))
  }
  tryCatch(
    {
      lubridate::force_tz(Sys.time(), tzone = tz_name)
      tz_name
    },
    error = function(e) {
      warning("Unknown timezone '", tz_name, "', falling back to UTC")
      "UTC"
    }
  )
}

.parse_dt <- function(value, params) {
  all_day <- grepl("VALUE=DATE", params, fixed = TRUE)
  tz_name <- if (grepl("TZID=", params, fixed = TRUE)) {
    sub(".*TZID=([^;]+).*", "\\1", params)
  } else {
    NULL
  }
  tz <- .resolve_tz(tz_name)

  dt <- if (all_day) {
    as.POSIXct(lubridate::ymd(value), tz = tz)
  } else if (grepl("Z$", value)) {
    lubridate::ymd_hms(value, tz = "UTC", quiet = TRUE)
  } else {
    lubridate::force_tz(lubridate::ymd_hms(value, quiet = TRUE), tz)
  }
  list(dt = dt, all_day = all_day)
}

#' Parse raw iCalendar text into a data frame of events.
#'
#' @param ics_text Character string of .ics file content.
#' @return Data frame with columns: uid, summary, dtstart (POSIXct), dtend,
#'   all_day (logical), rrule (character), source_url (NA by default).
parse_ics_text <- function(ics_text) {
  # Unfold continuation lines (RFC 5545 line folding: CRLF + LWSP)
  text <- gsub("\r\n[ \t]|\n[ \t]|\r[ \t]", "", ics_text)
  lines <- strsplit(text, "\r\n|\r|\n")[[1]]

  in_event <- FALSE
  events <- list()
  current <- list()

  for (line in lines) {
    if (line == "BEGIN:VEVENT") {
      in_event <- TRUE
      current <- list()
    } else if (line == "END:VEVENT") {
      in_event <- FALSE
      events[[length(events) + 1L]] <- current
    } else if (in_event && nchar(line) > 0L) {
      colon_pos <- regexpr(":", line, fixed = TRUE)[1L]
      if (colon_pos > 0L) {
        name_params <- substr(line, 1L, colon_pos - 1L)
        value <- substr(line, colon_pos + 1L, nchar(line))
        semi_pos <- regexpr(";", name_params, fixed = TRUE)[1L]
        if (semi_pos > 0L) {
          name <- substr(name_params, 1L, semi_pos - 1L)
          params <- substr(name_params, semi_pos + 1L, nchar(name_params))
        } else {
          name <- name_params
          params <- ""
        }
        # Keep first occurrence of each property (RFC 5545 allows some repeating)
        if (is.null(current[[name]])) {
          current[[name]] <- list(value = value, params = params)
        }
      }
    }
  }

  if (length(events) == 0L) {
    return(.empty_events())
  }

  rows <- lapply(events, function(ev) {
    # Skip cancelled events
    status <- ev[["STATUS"]]
    if (!is.null(status) && identical(status$value, "CANCELLED")) {
      return(NULL)
    }

    start_raw <- ev[["DTSTART"]]
    if (is.null(start_raw)) {
      return(NULL)
    }

    start_parsed <- tryCatch(
      .parse_dt(start_raw$value, start_raw$params),
      error = function(e) NULL
    )
    if (is.null(start_parsed) || is.na(start_parsed$dt)) {
      return(NULL)
    }

    end_raw <- ev[["DTEND"]]
    dtend <- if (!is.null(end_raw)) {
      tryCatch(
        .parse_dt(end_raw$value, end_raw$params)$dt,
        error = function(e) NA
      )
    } else {
      NA
    }

    summary_raw <- ev[["SUMMARY"]]

    data.frame(
      uid = (ev[["UID"]] %||%
        list(value = paste0("uid_", sample.int(1e9, 1))))$value,
      summary = (summary_raw %||% list(value = "(no title)"))$value,
      dtstart = start_parsed$dt,
      dtend = dtend,
      all_day = start_parsed$all_day,
      rrule = (ev[["RRULE"]] %||% list(value = NA_character_))$value,
      source_url = NA_character_,
      stringsAsFactors = FALSE
    )
  })

  result <- do.call(rbind, Filter(Negate(is.null), rows))
  if (is.null(result)) .empty_events() else result
}

.empty_events <- function() {
  data.frame(
    uid = character(),
    summary = character(),
    dtstart = as.POSIXct(character()),
    dtend = as.POSIXct(character()),
    all_day = logical(),
    rrule = character(),
    source_url = character(),
    stringsAsFactors = FALSE
  )
}

#' Expand recurring events within the date window [from, to].
expand_recurring <- function(df, from, to) {
  if (nrow(df) == 0L) {
    return(df)
  }

  has_rrule <- !is.na(df$rrule) & nchar(df$rrule) > 0L
  non_rec <- df[!has_rrule, ]
  rec <- df[has_rrule, ]

  if (nrow(rec) == 0L) {
    return(non_rec)
  }

  .parse_rrule <- function(s) {
    parts <- strsplit(s, ";", fixed = TRUE)[[1L]]
    out <- list()
    for (p in parts) {
      kv <- strsplit(p, "=", fixed = TRUE)[[1L]]
      if (length(kv) == 2L) out[[kv[1L]]] <- kv[2L]
    }
    out
  }

  end_window <- as.POSIXct(to + 1L)

  .expand_one <- function(row) {
    rr <- .parse_rrule(row$rrule)
    freq <- rr[["FREQ"]] %||% "DAILY"
    interval <- as.integer(rr[["INTERVAL"]] %||% "1")
    count <- if (!is.null(rr[["COUNT"]])) as.integer(rr[["COUNT"]]) else Inf
    until <- if (!is.null(rr[["UNTIL"]])) {
      tryCatch(
        lubridate::ymd_hms(rr[["UNTIL"]], tz = "UTC", quiet = TRUE),
        error = function(e) end_window
      )
    } else {
      end_window
    }
    end_date <- min(end_window, until)
    byday <- if (!is.null(rr[["BYDAY"]])) {
      strsplit(rr[["BYDAY"]], ",")[[1L]]
    } else {
      NULL
    }

    dtstart <- row$dtstart

    if (freq == "WEEKLY" && !is.null(byday)) {
      byday_nums <- unname(.ICS_WDAY[intersect(byday, names(.ICS_WDAY))])
      wday_of_start <- lubridate::wday(dtstart, week_start = 1L)
      week_mon <- dtstart - lubridate::days(wday_of_start - 1L)

      instances <- list()
      cur_week <- week_mon
      n_gen <- 0L

      while (cur_week < end_date && n_gen < count) {
        for (wd in sort(byday_nums)) {
          cand <- cur_week + lubridate::days(wd - 1L)
          if (cand >= dtstart && cand < end_date && n_gen < count) {
            instances[[length(instances) + 1L]] <- cand
            n_gen <- n_gen + 1L
          }
        }
        cur_week <- cur_week + lubridate::weeks(interval)
      }
      dates <- if (length(instances) > 0L) do.call(c, instances) else c()
    } else {
      by_str <- switch(
        freq,
        DAILY = paste0(interval, " days"),
        WEEKLY = paste0(interval * 7L, " days"),
        MONTHLY = paste0(interval, " months"),
        YEARLY = paste0(interval, " years"),
        NULL
      )
      if (is.null(by_str)) {
        warning("Unsupported RRULE FREQ=", freq, " — skipping")
        return(NULL)
      }
      dates <- seq(dtstart, end_date, by = by_str)
      dates <- dates[dates >= dtstart & dates < end_date]
      if (is.finite(count)) dates <- head(dates, count)
    }

    dates <- dates[as.Date(dates) >= from & as.Date(dates) <= to]
    if (length(dates) == 0L) {
      return(NULL)
    }

    duration <- if (!is.na(row$dtend)) {
      as.numeric(row$dtend - row$dtstart, units = "secs")
    } else {
      3600
    }
    result <- row[rep(1L, length(dates)), ]
    result$dtstart <- dates
    result$dtend <- dates + duration
    result$rrule <- NA_character_
    rownames(result) <- NULL
    result
  }

  expanded <- do.call(
    rbind,
    Filter(
      Negate(is.null),
      lapply(seq_len(nrow(rec)), function(i) .expand_one(rec[i, ]))
    )
  )
  rbind(
    non_rec,
    if (!is.null(expanded) && nrow(expanded) > 0L) expanded else .empty_events()
  )
}

#' Download and parse a single ICS URL, filtered to [from, to].
fetch_one_ics <- function(url, from, to) {
  ics_text <- httr2::request(url) |>
    httr2::req_timeout(30L) |>
    httr2::req_perform() |>
    httr2::resp_body_string()

  df <- parse_ics_text(ics_text)
  if (nrow(df) == 0L) {
    return(df)
  }
  df$source_url <- url

  df <- expand_recurring(df, from, to)
  df[
    !is.na(df$dtstart) &
      as.Date(df$dtstart) >= from &
      as.Date(df$dtstart) <= to,
  ]
}

#' Fetch and merge events from multiple ICS URLs.
#'
#' @param urls Character vector of ICS feed URLs.
#' @param from,to Date range (inclusive) to filter events.
#' @return Merged, deduplicated data frame of events.
fetch_ics_events <- function(urls, from = Sys.Date(), to = Sys.Date() + 40L) {
  results <- lapply(urls, function(url) {
    tryCatch(
      fetch_one_ics(url, from, to),
      error = function(e) {
        warning("Failed to fetch ICS from ", url, ": ", conditionMessage(e))
        NULL
      }
    )
  })
  results <- Filter(function(x) !is.null(x) && nrow(x) > 0L, results)
  if (length(results) == 0L) {
    return(.empty_events())
  }
  df <- do.call(rbind, results)
  df[!duplicated(df$uid), ]
}

# ── Google Tasks ──────────────────────────────────────────────────────────────

#' Get a cached gargle OAuth token for the Google Tasks API.
#'
#' On first call this opens a browser for the OAuth dance. Subsequent calls
#' read the cached token from `cache_path` silently. Returns NULL on failure
#' so the caller can render without the tasks panel.
#'
#' Setup (one-time, interactive):
#'   1. Create a GCP project, enable Tasks API, download OAuth client JSON.
#'   2. Place the JSON at app/data/gcp-client.json.
#'   3. Call get_tasks_token() once in an interactive R session.
get_tasks_token <- function(
  client_json = "app/data/gcp-client.json",
  cache_path = "app/data/gargle-token.rds",
  email = NULL
) {
  if (!requireNamespace("gargle", quietly = TRUE)) {
    message(
      "gargle not installed — skipping Google Tasks. Install with: install.packages('gargle')"
    )
    return(NULL)
  }
  if (!file.exists(client_json)) {
    message(
      "GCP client JSON not found at '",
      client_json,
      "' — skipping Google Tasks"
    )
    return(NULL)
  }
  tryCatch(
    {
      client <- gargle::gargle_oauth_client_from_json(
        client_json,
        name = "trmnlr"
      )
      gargle::credentials_user_oauth2(
        scopes = "https://www.googleapis.com/auth/tasks.readonly",
        client = client,
        cache = cache_path,
        email = email
      )
    },
    error = function(e) {
      warning("Google Tasks auth failed: ", conditionMessage(e))
      NULL
    }
  )
}

#' Fetch incomplete tasks from the Google Tasks API.
#'
#' @param token gargle token from get_tasks_token(), or NULL.
#' @return Data frame with columns: title (character), due (Date or NA).
fetch_tasks <- function(token, tasklist = "@default", max_results = 20L) {
  empty <- data.frame(
    title = character(),
    due = as.Date(character()),
    stringsAsFactors = FALSE
  )
  if (is.null(token)) {
    return(empty)
  }

  access_token <- tryCatch(token$credentials$access_token, error = function(e) {
    NULL
  })
  if (is.null(access_token)) {
    return(empty)
  }

  resp <- tryCatch(
    httr2::request("https://tasks.googleapis.com/tasks/v1/lists") |>
      httr2::req_url_path_append(tasklist, "tasks") |>
      httr2::req_url_query(showCompleted = "false", maxResults = max_results) |>
      httr2::req_auth_bearer_token(access_token) |>
      httr2::req_perform() |>
      httr2::resp_body_json(),
    error = function(e) {
      warning("Google Tasks fetch failed: ", conditionMessage(e))
      list(items = list())
    }
  )

  items <- resp$items %||% list()
  if (length(items) == 0L) {
    return(empty)
  }

  data.frame(
    title = sapply(items, function(x) x$title %||% "(no title)"),
    due = as.Date(sapply(items, function(x) {
      if (!is.null(x$due)) substr(x$due, 1L, 10L) else NA_character_
    })),
    stringsAsFactors = FALSE
  )
}

# ── Calendar grid (ggplot2) ───────────────────────────────────────────────────

#' Build a 42-cell data frame representing a month calendar grid.
#'
#' @param year,month Integer year and month.
#' @param events Data frame from fetch_ics_events(), pre-filtered to this month.
#' @param week_start 1 = Monday (ISO/European), 7 = Sunday (US).
#' @param today Date used to highlight the current day.
build_calendar_df <- function(
  year = as.integer(format(Sys.Date(), "%Y")),
  month = as.integer(format(Sys.Date(), "%m")),
  events = .empty_events(),
  week_start = 1L,
  today = Sys.Date()
) {
  first_day <- as.Date(paste(year, sprintf("%02d", month), "01", sep = "-"))
  last_day <- seq(first_day, by = "month", length.out = 2L)[2L] - 1L
  first_wday <- lubridate::wday(first_day, week_start = week_start)
  start_date <- first_day - (first_wday - 1L)
  all_dates <- seq(start_date, by = "day", length.out = 42L)

  df <- data.frame(
    date = all_dates,
    col = ((seq_along(all_dates) - 1L) %% 7L) + 1L,
    row = ((seq_along(all_dates) - 1L) %/% 7L) + 1L,
    stringsAsFactors = FALSE
  )
  df$in_month <- df$date >= first_day & df$date <= last_day
  df$day_num <- ifelse(
    df$in_month,
    as.integer(format(df$date, "%d")),
    NA_integer_
  )
  df$is_today <- df$in_month & df$date == today

  if (nrow(events) > 0L && "dtstart" %in% names(events)) {
    event_dates <- as.Date(events$dtstart)
    df$has_event <- df$in_month & (df$date %in% event_dates)
  } else {
    df$has_event <- FALSE
  }

  df
}

#' Build ggplot2 calendar for one month.
make_calendar_plot <- function(cal_df, year, month) {
  month_label <- format(
    as.Date(paste(year, sprintf("%02d", month), "01", sep = "-")),
    "%B %Y"
  )

  wday_labels <- c("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su")
  header_df <- data.frame(
    col = seq_len(7L),
    label = wday_labels,
    stringsAsFactors = FALSE
  )

  used_rows <- if (any(cal_df$in_month)) {
    max(cal_df$row[cal_df$in_month])
  } else {
    5L
  }
  plot_df <- cal_df[cal_df$row <= used_rows, ]

  ggplot(plot_df, aes(x = col, y = -row)) +
    # Day tiles: black fill for today, white for others
    geom_tile(
      aes(fill = is_today),
      colour = "grey55",
      linewidth = 0.4,
      width = 0.95,
      height = 0.90,
      show.legend = FALSE
    ) +
    scale_fill_manual(values = c("FALSE" = "white", "TRUE" = "black")) +
    # Day numbers: white text on today, black otherwise
    geom_text(
      aes(label = day_num, colour = is_today, y = -row + 0.20),
      size = 3.0,
      fontface = "bold",
      na.rm = TRUE,
      show.legend = FALSE
    ) +
    scale_colour_manual(values = c("FALSE" = "black", "TRUE" = "white")) +
    # Dot indicator for days with events
    geom_point(
      data = \(d) subset(d, has_event & in_month),
      aes(y = -row - 0.28),
      size = 1.0,
      colour = "black",
      shape = 16,
      na.rm = TRUE,
      inherit.aes = TRUE
    ) +
    # Weekday column headers (separate data layer)
    geom_text(
      data = header_df,
      aes(x = col, y = 0.62, label = label),
      size = 2.7,
      fontface = "bold",
      colour = "black",
      inherit.aes = FALSE
    ) +
    labs(title = month_label) +
    scale_x_continuous(expand = expansion(add = 0.55)) +
    scale_y_continuous(expand = expansion(add = 0.45)) +
    theme_void(base_size = 9L) +
    theme(
      plot.title = element_text(
        hjust = 0.5,
        face = "bold",
        size = 10L,
        margin = margin(t = 3L, b = 3L)
      ),
      plot.background = element_rect(fill = "white", colour = NA),
      plot.margin = margin(2L, 2L, 2L, 2L)
    )
}

# ── Right panel (grid primitives) ─────────────────────────────────────────────

.truncate <- function(x, n = 26L) {
  ifelse(nchar(x) > n, paste0(substr(x, 1L, n - 1L), "…"), x)
}

#' Build the right-panel grob containing tasks and upcoming events.
#'
#' @param tasks   Data frame from fetch_tasks().
#' @param upcoming Data frame of next N events (subset of fetch_ics_events()).
make_right_panel_grob <- function(
  tasks,
  upcoming,
  max_tasks = 10L,
  max_upcoming = 7L
) {
  children <- list()

  x_left <- 0.07 # left margin (npc)
  y <- 0.96 # current y, top-down
  dy_head <- 0.058 # heading height (≈ 28px at 480px)
  dy_item <- 0.068 # item row height (≈ 33px)
  dy_evt <- 0.072 # upcoming event height

  .add <- function(grob) {
    children[[length(children) + 1L]] <<- grob
  }

  # ── Tasks section ────────────────────────────────────────────────────────────
  .add(grid::textGrob(
    "Tasks",
    x = grid::unit(x_left, "npc"),
    y = grid::unit(y, "npc"),
    hjust = 0L,
    vjust = 1L,
    gp = grid::gpar(fontsize = 9L, fontface = "bold")
  ))
  y <- y - dy_head

  n_tasks <- min(max_tasks, nrow(tasks))
  if (n_tasks > 0L) {
    for (i in seq_len(n_tasks)) {
      if (y < 0.54) {
        break
      }
      .add(grid::textGrob(
        paste0("• ", .truncate(tasks$title[i])),
        x = grid::unit(x_left, "npc"),
        y = grid::unit(y, "npc"),
        hjust = 0L,
        vjust = 1L,
        gp = grid::gpar(fontsize = 7.5)
      ))
      y <- y - dy_item
    }
  } else {
    .add(grid::textGrob(
      "(no tasks)",
      x = grid::unit(x_left, "npc"),
      y = grid::unit(y, "npc"),
      hjust = 0L,
      vjust = 1L,
      gp = grid::gpar(fontsize = 7.5, col = "grey60")
    ))
  }

  # ── Horizontal divider ────────────────────────────────────────────────────────
  div_y <- 0.50
  .add(grid::linesGrob(
    x = grid::unit(c(0.03, 0.97), "npc"),
    y = grid::unit(c(div_y, div_y), "npc"),
    gp = grid::gpar(lwd = 0.8, col = "black")
  ))

  # ── Upcoming section ─────────────────────────────────────────────────────────
  y <- div_y - 0.02
  .add(grid::textGrob(
    "Upcoming",
    x = grid::unit(x_left, "npc"),
    y = grid::unit(y, "npc"),
    hjust = 0L,
    vjust = 1L,
    gp = grid::gpar(fontsize = 9L, fontface = "bold")
  ))
  y <- y - dy_head

  n_upcoming <- min(max_upcoming, nrow(upcoming))
  if (n_upcoming > 0L) {
    for (i in seq_len(n_upcoming)) {
      if (y < 0.02) {
        break
      }
      ev <- upcoming[i, ]
      dt <- ev$dtstart
      time_str <- if (isTRUE(ev$all_day)) {
        format(as.Date(dt), "%b %d")
      } else {
        format(dt, "%b %d %H:%M")
      }
      label <- paste0(time_str, "  ", .truncate(ev$summary, 20L))
      .add(grid::textGrob(
        label,
        x = grid::unit(x_left, "npc"),
        y = grid::unit(y, "npc"),
        hjust = 0L,
        vjust = 1L,
        gp = grid::gpar(fontsize = 7.5)
      ))
      y <- y - dy_evt
    }
  } else {
    .add(grid::textGrob(
      "(no upcoming events)",
      x = grid::unit(x_left, "npc"),
      y = grid::unit(y, "npc"),
      hjust = 0L,
      vjust = 1L,
      gp = grid::gpar(fontsize = 7.5, col = "grey60")
    ))
  }

  grid::gTree(children = do.call(grid::gList, children))
}

# ── Entry point ───────────────────────────────────────────────────────────────

#' Generate the calendar dashboard BMP image.
#'
#' @param ics_urls  Character vector of public ICS feed URLs.
#' @param output    Output path for the BMP file.
#' @param tasks_token gargle token from get_tasks_token(), or NULL to omit tasks.
#' @param week_start 1 = Monday (ISO/European default), 7 = Sunday.
#' @param tz        Timezone for event display (defaults to system timezone).
#' @param today     Date used as "today" for highlighting and upcoming filter.
render_calendar_bmp <- function(
  ics_urls,
  output = "app/images/calendar.bmp",
  tasks_token = NULL,
  week_start = 1L,
  tz = Sys.timezone(),
  today = Sys.Date()
) {
  year <- as.integer(format(today, "%Y"))
  month <- as.integer(format(today, "%m"))
  from <- lubridate::floor_date(today, "month")
  # Fetch a bit beyond month end so upcoming panel sees near-future events
  to <- lubridate::ceiling_date(today, "month") - 1L + 21L

  # ── Fetch data ────────────────────────────────────────────────────────────
  events <- if (length(ics_urls) > 0L) {
    tryCatch(
      fetch_ics_events(ics_urls, from = from, to = to),
      error = function(e) {
        warning("ICS fetch error: ", conditionMessage(e))
        .empty_events()
      }
    )
  } else {
    .empty_events()
  }

  # Convert to local timezone for display
  if (nrow(events) > 0L && !is.null(tz) && nzchar(tz)) {
    events$dtstart <- lubridate::with_tz(events$dtstart, tz)
    events$dtend <- lubridate::with_tz(events$dtend, tz)
  }

  tasks <- fetch_tasks(tasks_token)

  # Events for this month's calendar grid
  month_events <- if (nrow(events) > 0L) {
    events[format(as.Date(events$dtstart), "%Y-%m") == format(today, "%Y-%m"), ]
  } else {
    .empty_events()
  }

  # Next N future events for the side panel
  upcoming <- if (nrow(events) > 0L) {
    future <- events[as.Date(events$dtstart) >= today, ]
    future <- future[order(future$dtstart), ]
    head(future, 7L)
  } else {
    .empty_events()
  }

  # ── Build visuals ─────────────────────────────────────────────────────────
  cal_df <- build_calendar_df(year, month, month_events, week_start, today)
  cal_plot <- make_calendar_plot(cal_df, year, month)
  right_grob <- make_right_panel_grob(tasks, upcoming)

  # ── Render ────────────────────────────────────────────────────────────────
  tmp <- tempfile(fileext = ".bmp")
  bmp(tmp, width = 800L, height = 480L, bg = "white", type = "cairo")

  grid::grid.newpage()
  layout <- grid::grid.layout(
    nrow = 1L,
    ncol = 2L,
    widths = grid::unit(c(533L, 267L), "points")
  )
  grid::pushViewport(grid::viewport(layout = layout))

  # Left 2/3: calendar
  grid::pushViewport(grid::viewport(layout.pos.col = 1L, layout.pos.row = 1L))
  grid::grid.draw(ggplot2::ggplotGrob(cal_plot))
  grid::popViewport()

  # Right 1/3: vertical divider + panel
  grid::pushViewport(grid::viewport(layout.pos.col = 2L, layout.pos.row = 1L))
  grid::grid.lines(
    x = grid::unit(c(0, 0), "npc"),
    y = grid::unit(c(0.02, 0.98), "npc"),
    gp = grid::gpar(col = "black", lwd = 0.8)
  )
  grid::grid.draw(right_grob)
  grid::popViewport()

  grid::popViewport()
  dev.off()

  convert_for_trmnl(tmp, output)
  message("Calendar image written to: ", output)
  invisible(output)
}

local({
  ics_urls <- Filter(
    nzchar,
    c(Sys.getenv("GOOGLE_ICS_URL"), Sys.getenv("OUTLOOK_ICS_URL"))
  )
  render_calendar_bmp(ics_urls, tasks_token = get_tasks_token())
})
