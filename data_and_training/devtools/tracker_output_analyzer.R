#!/usr/bin/env Rscript

library(shiny)
library(ggplot2)
library(jsonlite)

category_colors <- c()

frame_json <- '{"record_type":"frame","frame_index":42,"timestamp_ms":516870,"detections":{"detections":[{"categories":[{"score":0.5662453174591064,"index":-1,"categoryName":"apple","displayName":""}],"keypoints":[],"boundingBox":{"originX":392,"originY":222,"width":91,"height":84,"angle":0}},{"categories":[{"score":0.49443426728248596,"index":-1,"categoryName":"knife","displayName":""}],"keypoints":[],"boundingBox":{"originX":5,"originY":247,"width":331,"height":215,"angle":0}}]},"tracker_state":{"timestamp":516870,"tracks":[{"instanceId":"#3","status":"CONFIRMED","center":{"centerX":437.5,"centerY":264},"boundingBox":{"originX":392,"originY":222,"width":91,"height":84,"angle":0},"velocity":{"vx":0.001976318484383,"vy":-0.0040081925243215565},"history":[{"timestamp":516370,"category":"apple","detectionConfidence":0.4609032869338989,"boundingBox":{"originX":391,"originY":223,"width":91,"height":86,"angle":0},"center":{"centerX":436.5,"centerY":266}},{"timestamp":516495,"category":"apple","detectionConfidence":0.5980575084686279,"boundingBox":{"originX":391,"originY":223,"width":91,"height":85,"angle":0},"center":{"centerX":436.5,"centerY":265.5}},{"timestamp":516620,"category":"apple","detectionConfidence":0.5767316818237305,"boundingBox":{"originX":389,"originY":223,"width":92,"height":85,"angle":0},"center":{"centerX":435,"centerY":265.5}},{"timestamp":516746,"category":"apple","detectionConfidence":0.49711766839027405,"boundingBox":{"originX":392,"originY":223,"width":90,"height":84,"angle":0},"center":{"centerX":437,"centerY":265}},{"timestamp":516870,"category":"apple","detectionConfidence":0.5662453174591064,"boundingBox":{"originX":392,"originY":222,"width":91,"height":84,"angle":0},"center":{"centerX":437.5,"centerY":264}}],"categoryHistory":{},"currentCategory":"apple","lastDetectionConfidence":0.5662453174591064,"hasBeenConfirmed":true,"createdAt":513362,"updatedAt":516870,"consecutiveHits":29,"consecutiveMisses":0},{"instanceId":"#4","status":"TEMPORARILY_MISSING","center":{"centerX":185,"centerY":342.5},"boundingBox":{"originX":33,"originY":219,"width":304,"height":247,"angle":0},"velocity":{"vx":0.07258064516129033,"vy":0.04838709677419355},"history":[{"timestamp":516246,"category":"banana","detectionConfidence":0.3583239018917084,"boundingBox":{"originX":12,"originY":241,"width":328,"height":191,"angle":0},"center":{"centerX":176,"centerY":336.5}},{"timestamp":516370,"category":"spoon","detectionConfidence":0.377849817276001,"boundingBox":{"originX":33,"originY":219,"width":304,"height":247,"angle":0},"center":{"centerX":185,"centerY":342.5}}],"categoryHistory":{},"currentCategory":"spoon","lastDetectionConfidence":0.377849817276001,"hasBeenConfirmed":true,"createdAt":516246,"updatedAt":516370,"consecutiveHits":0,"consecutiveMisses":4},{"instanceId":"#5","status":"CONFIRMED","center":{"centerX":170.5,"centerY":354.5},"boundingBox":{"originX":5,"originY":247,"width":331,"height":215,"angle":0},"velocity":{"vx":-0.020225294418842805,"vy":-0.009600614439324116},"history":[{"timestamp":516620,"category":"knife","detectionConfidence":0.40514615178108215,"boundingBox":{"originX":19,"originY":254,"width":313,"height":206,"angle":0},"center":{"centerX":175.5,"centerY":357}},{"timestamp":516746,"category":"knife","detectionConfidence":0.4885427951812744,"boundingBox":{"originX":16,"originY":240,"width":321,"height":219,"angle":0},"center":{"centerX":176.5,"centerY":349.5}},{"timestamp":516870,"category":"knife","detectionConfidence":0.49443426728248596,"boundingBox":{"originX":5,"originY":247,"width":331,"height":215,"angle":0},"center":{"centerX":170.5,"centerY":354.5}}],"categoryHistory":{},"currentCategory":"knife","lastDetectionConfidence":0.49443426728248596,"hasBeenConfirmed":true,"createdAt":516620,"updatedAt":516870,"consecutiveHits":3,"consecutiveMisses":0}]}}'
previous_frame_json <- '{"record_type":"frame","frame_index":41,"timestamp_ms":516746,"detections":{"detections":[{"categories":[{"score":0.49711766839027405,"index":-1,"categoryName":"apple","displayName":""}],"keypoints":[],"boundingBox":{"originX":392,"originY":223,"width":90,"height":84,"angle":0}},{"categories":[{"score":0.4885427951812744,"index":-1,"categoryName":"knife","displayName":""}],"keypoints":[],"boundingBox":{"originX":16,"originY":240,"width":321,"height":219,"angle":0}}]},"tracker_state":{"timestamp":516746,"tracks":[{"instanceId":"#3","status":"CONFIRMED","center":{"centerX":437,"centerY":265},"boundingBox":{"originX":392,"originY":223,"width":90,"height":84,"angle":0},"velocity":{"vx":-0.0010478750640040965,"vy":-0.001992063492063492},"history":[{"timestamp":516246,"category":"apple","detectionConfidence":0.5147239565849304,"boundingBox":{"originX":391,"originY":223,"width":93,"height":86,"angle":0},"center":{"centerX":437.5,"centerY":266}},{"timestamp":516370,"category":"apple","detectionConfidence":0.4609032869338989,"boundingBox":{"originX":391,"originY":223,"width":91,"height":86,"angle":0},"center":{"centerX":436.5,"centerY":266}},{"timestamp":516495,"category":"apple","detectionConfidence":0.5980575084686279,"boundingBox":{"originX":391,"originY":223,"width":91,"height":85,"angle":0},"center":{"centerX":436.5,"centerY":265.5}},{"timestamp":516620,"category":"apple","detectionConfidence":0.5767316818237305,"boundingBox":{"originX":389,"originY":223,"width":92,"height":85,"angle":0},"center":{"centerX":435,"centerY":265.5}},{"timestamp":516746,"category":"apple","detectionConfidence":0.49711766839027405,"boundingBox":{"originX":392,"originY":223,"width":90,"height":84,"angle":0},"center":{"centerX":437,"centerY":265}}],"categoryHistory":{},"currentCategory":"apple","lastDetectionConfidence":0.49711766839027405,"hasBeenConfirmed":true,"createdAt":513362,"updatedAt":516746,"consecutiveHits":28,"consecutiveMisses":0},{"instanceId":"#4","status":"TEMPORARILY_MISSING","center":{"centerX":185,"centerY":342.5},"boundingBox":{"originX":33,"originY":219,"width":304,"height":247,"angle":0},"velocity":{"vx":0.07258064516129033,"vy":0.04838709677419355},"history":[{"timestamp":516246,"category":"banana","detectionConfidence":0.3583239018917084,"boundingBox":{"originX":12,"originY":241,"width":328,"height":191,"angle":0},"center":{"centerX":176,"centerY":336.5}},{"timestamp":516370,"category":"spoon","detectionConfidence":0.377849817276001,"boundingBox":{"originX":33,"originY":219,"width":304,"height":247,"angle":0},"center":{"centerX":185,"centerY":342.5}}],"categoryHistory":{},"currentCategory":"spoon","lastDetectionConfidence":0.377849817276001,"hasBeenConfirmed":true,"createdAt":516246,"updatedAt":516370,"consecutiveHits":0,"consecutiveMisses":3},{"instanceId":"#5","status":"CONFIRMED","center":{"centerX":176.5,"centerY":349.5},"boundingBox":{"originX":16,"originY":240,"width":321,"height":219,"angle":0},"velocity":{"vx":0.007936507936507936,"vy":-0.05952380952380952},"history":[{"timestamp":516620,"category":"knife","detectionConfidence":0.40514615178108215,"boundingBox":{"originX":19,"originY":254,"width":313,"height":206,"angle":0},"center":{"centerX":175.5,"centerY":357}},{"timestamp":516746,"category":"knife","detectionConfidence":0.4885427951812744,"boundingBox":{"originX":16,"originY":240,"width":321,"height":219,"angle":0},"center":{"centerX":176.5,"centerY":349.5}}],"categoryHistory":{},"currentCategory":"knife","lastDetectionConfidence":0.4885427951812744,"hasBeenConfirmed":true,"createdAt":516620,"updatedAt":516746,"consecutiveHits":2,"consecutiveMisses":0}]}}'

read_jsonl <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
}

# Persistent mapping: new categories receive new colors as they appear.
get_category_color <- function(category) {
  for (value in unique(category)) {
    if (is.na(value) || value %in% names(category_colors)) {
      next
    }

    hue <- (length(category_colors) * 137.508) %% 360

    category_colors[value] <<- grDevices::hcl(
      h = hue,
      c = 65,
      l = 55
    )
  }

  category_colors
}

draw_frame <- function(frame_json) {
  frame <- jsonlite::fromJSON(
    frame_json,
    simplifyVector = FALSE
  )

  tracks <- frame$tracker_state$tracks

  # Collect historical centers for every track.
  history <- do.call(
    rbind,
    lapply(tracks, function(track) {
      track_history <- track$history

      if (length(track_history) == 0) {
        return(NULL)
      }

      data.frame(
        x = vapply(track_history, function(r) r$center$centerX, numeric(1)),
        y = vapply(track_history, function(r) r$center$centerY, numeric(1)),
        instanceId = track$instanceId,
        category = vapply(
          track_history,
          function(r) {
            if (is.null(r$category) || !nzchar(r$category)) {
              "(unknown)"
            } else {
              r$category
            }
          },
          character(1)
        ),
        order = seq_along(track_history)
      )
    })
  )

  # Ensure every category in this frame has a persistent color
  if (!is.null(history) && nrow(history) > 0) {
    get_category_color(history$category)
  }

  # Build segments from each historical point to the next.
  arrows <- if (!is.null(history) && nrow(history) > 0) {
    do.call(
      rbind,
      lapply(split(history, history$instanceId), function(track_history) {
        track_history <- track_history[order(track_history$order), ]

        if (nrow(track_history) < 2) {
          return(NULL)
        }

        data.frame(
          x = head(track_history$x, -1),
          y = head(track_history$y, -1),
          xend = tail(track_history$x, -1),
          yend = tail(track_history$y, -1),
          category = tail(track_history$category, -1),
          instanceId = track_history$instanceId[-nrow(track_history)]
        )
      })
    )
  } else {
    NULL
  }

  label_positions <- if (!is.null(history) && nrow(history) > 0) {
    do.call(
      rbind,
      lapply(split(history, history$instanceId), function(track_history) {
        track_history <- track_history[order(track_history$order), ]

        x <- track_history$x
        y <- track_history$y

        if (length(x) == 1) {
          return(data.frame(
            x = x[1],
            y = y[1],
            instanceId = track_history$instanceId[1]
          ))
        }

        distances <- sqrt(diff(x)^2 + diff(y)^2)
        total_distance <- sum(distances)

        if (total_distance == 0) {
          mid <- ceiling(length(x) / 2)

          return(data.frame(
            x = x[mid],
            y = y[mid],
            instanceId = track_history$instanceId[1]
          ))
        }

        target <- total_distance / 2
        cumulative <- cumsum(distances)
        segment <- which(cumulative >= target)[1]

        distance_before <- if (segment == 1) {
          0
        } else {
          cumulative[segment - 1]
        }

        fraction <- (target - distance_before) / distances[segment]

        data.frame(
          x = x[segment] + fraction * (x[segment + 1] - x[segment]),
          y = y[segment] + fraction * (y[segment + 1] - y[segment]),
          instanceId = track_history$instanceId[1]
        )
      })
    )
  } else {
    NULL
  }

  ggplot(
    history,
    aes(x = x, y = y, color = instanceId)
  ) +
    # Arrows colored by the destination observation's category.
    geom_segment(
      data = arrows,
      aes(
        x = x,
        y = y,
        xend = xend,
        yend = yend,
        color = category
      ),
      arrow = grid::arrow(
        length = grid::unit(0.12, "inches"),
        type = "closed"
      ),
      linewidth = 0.7,
      inherit.aes = FALSE
    ) +
    # Points at each historical position colored by their recorded category
    geom_point(
      aes(color = category),
      size = 3
    ) +
    # One readable instance ID label per track.
    geom_label(
      data = label_positions,
      aes(x = x, y = y, label = instanceId),
      color = "black",
      fill = NA,
      label.size = 0,
      label.padding = grid::unit(0.1, "lines"),
      size = 3,
      inherit.aes = FALSE
    ) +
    # Retain category colors and legend entries across frames.
    scale_color_manual(
      name = "Category",
      values = category_colors,
      limits = names(category_colors),
      breaks = names(category_colors),
      drop = FALSE
    ) +
    scale_x_continuous(
      limits = c(0, 640),
      position = "top",
      expand = c(0, 0)
    ) +
    scale_y_reverse(
      limits = c(480, 0),
      expand = c(0, 0)
    ) +
    coord_fixed() +
    theme_minimal()
}

draw_presence_timeline <- function(
  frame_json,
  target_sampling_fps,
  window = 10,
  tolerance_ms = 40
) {
  frame <- jsonlite::fromJSON(
    frame_json,
    simplifyVector = FALSE
  )

  current_ts <- frame$timestamp_ms
  interval_ms <- 1000 / target_sampling_fps

  tracks <- frame$tracker_state$tracks

  if (length(tracks) == 0) {
    return(
      ggplot() +
        theme_void()
    )
  }

  timeline <- do.call(
    rbind,
    lapply(tracks, function(track) {

      track_history <- track$history

      # Expected sampling timestamps, relative to the current frame.
      steps <- seq(-(window - 1), 0)

      expected_ts <- current_ts + steps * interval_ms

      # Start with unknown states.
      states <- rep("Unknown", length(steps))

      # Before the track was first created, it cannot have been present.
      if (!is.null(track$createdAt)) {
        states[expected_ts < track$createdAt] <- "Before first sighting"
      }

      # Extract and sort successful observation timestamps.
      if (length(track_history) > 0) {
        history_ts <- vapply(
          track_history,
          function(observation) {
            as.numeric(observation$timestamp)
          },
          numeric(1)
        )

        history_ts <- sort(history_ts)

        # Match each observation to its nearest expected sampling step.
        matched_steps <- integer(0)

        for (observation_ts in history_ts) {
          differences <- abs(expected_ts - observation_ts)
          nearest_index <- which.min(differences)

          if (differences[nearest_index] <= tolerance_ms) {
            # If multiple observations map to one step, keep the closest.
            if (!(nearest_index %in% matched_steps)) {
              states[nearest_index] <- "Present"
              matched_steps <- c(matched_steps, nearest_index)
            }
          }
        }

        # Infer missing samples only between matched observations.
        if (length(matched_steps) >= 2) {
          first_match <- min(matched_steps)
          last_match <- max(matched_steps)

          between_matches <- seq(first_match, last_match)

          states[
            between_matches[
              states[between_matches] == "Unknown"
            ]
          ] <- "Missing"
        }
      }

      # Use current tracker status to classify consecutive recent misses.
      consecutive_misses <- track$consecutiveMisses

      if (
        identical(track$status, "TEMPORARILY_MISSING") &&
        !is.null(consecutive_misses) &&
        consecutive_misses > 0
      ) {
        first_missing_step <- max(
          -window,
          -(consecutive_misses - 1)
        )

        states[steps >= first_missing_step] <- "Missing"
      }

      has_been_confirmed <- if (isTRUE(track$hasBeenConfirmed)) { "✅" } else { "❌" }

      data.frame(
        instanceId = as.character(track$instanceId),
        step = c(-window, steps),
        state = c(has_been_confirmed, states),
        confirmation = c(has_been_confirmed, rep(NA_character_, length(states))),
        isConfirmation = c(TRUE, rep(FALSE, length(states)))
      )
    })
  )

  timeline$instanceId <- factor(
    timeline$instanceId,
    levels = rev(unique(timeline$instanceId))
  )

  timeline$state <- factor(
    timeline$state,
    levels = c(
      "Present",
      "Missing",
      "Unknown",
      "Before first sighting"
    )
  )

  state_colors <- c(
    "Present" = "#4CAF50",
    "Missing" = "#E57373",
    "Unknown" = "#BDBDBD",
    "Before first sighting" = "white"
  )

  ggplot(
    timeline,
    aes(
      x = step,
      y = instanceId,
    )
  ) +
    geom_tile(
      data = subset(timeline, !isConfirmation),
      aes(fill = state),
      color = "grey70",
      linewidth = 0.3,
    ) +
    geom_text(
      data = subset(timeline, isConfirmation),
      aes(label = confirmation),
      size = 4,
      inherit.aes = TRUE
    ) +
    scale_fill_manual(
      values = state_colors,
      drop = FALSE
    ) +
    scale_x_continuous(
      breaks = seq(-window, 0),
      labels = c("Confirmed", as.character(seq(-(window - 1), 0))),
      expand = expansion(add = 0.5)
    ) +
    labs(
      title = "Track presence",
      x = "Sampling steps relative to current frame",
      y = "Track ID",
      fill = "State"
    ) +
    theme_minimal() +
    theme(
      panel.grid = element_blank(),
      axis.text.x = element_text(angle = 0)
    )
}

calculate_detection_track_comparisons <- function(
  frame_i_json,
  frame_i_minus_one_json
) {
  frame_i <- jsonlite::fromJSON(
    frame_i_json,
    simplifyVector = FALSE
  )

  frame_i_minus_one <- jsonlite::fromJSON(
    frame_i_minus_one_json,
    simplifyVector = FALSE
  )

  detections <- frame_i$detections$detections
  tracks <- frame_i_minus_one$tracker_state$tracks

  detection_names <- if (length(detections) > 0) {
    paste("Detection", seq_along(detections) - 1)
  } else {
    character(0)
  }

  result <- data.frame(
    `Track / measurement` = character(),
    check.names = FALSE
  )

  # Create one column for each detection.
  for (name in detection_names) {
    result[[name]] <- character()
  }

  # Return an empty comparison table if there are no tracks.
  if (length(tracks) == 0) {
    return(result)
  }

  for (track in tracks) {

    # Predict the track center at the current frame timestamp.
    dt <- frame_i$timestamp_ms - track$updatedAt

    prediction_x <- track$center$centerX + track$velocity$vx * dt
    prediction_y <- track$center$centerY + track$velocity$vy * dt

    distances <- character(length(detections))
    category_matches <- character(length(detections))

    for (i in seq_along(detections)) {
      detection <- detections[[i]]

      # Calculate detection center from its bounding box.
      box <- detection$boundingBox

      detection_x <- box$originX + box$width / 2
      detection_y <- box$originY + box$height / 2

      # Euclidean distance between detection and predicted track center.
      distance <- sqrt(
        (detection_x - prediction_x)^2 +
        (detection_y - prediction_y)^2
      )

      distances[i] <- sprintf("%.1f px", distance)

      # Compare detection category with the track's current category.
      detection_category <- detection$categories[[1]]$categoryName

      category_matches[i] <- if (
        identical(detection_category, track$currentCategory)
      ) {
        "✅"
      } else {
        "❌"
      }
    }

    # Add the distance row.
    distance_row <- as.data.frame(
      as.list(c(
        paste("Track", track$instanceId, "- Distance"),
        distances
      )),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )

    names(distance_row) <- c(
      "Track / measurement",
      detection_names
    )

    # Add the category comparison row.
    category_row <- as.data.frame(
      as.list(c(
        paste("Track", track$instanceId, "- Category match"),
        category_matches
      )),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )

    names(category_row) <- c(
      "Track / measurement",
      detection_names
    )

    result <- rbind(
      result,
      distance_row,
      category_row
    )
  }

  result
}

ui <- fluidPage(
  tags$head(
    tags$style(HTML("
      html, body {
        height: 100%;
        margin: 0;
        overflow: hidden;
      }

      .container-fluid {
        height: 100vh;
        padding: 10px 15px;
        box-sizing: border-box;
        display: grid;
        grid-template-rows: 45px minmax(0, 1fr) 180px;
        gap: 10px;
      }

      .app-header {
        min-height: 0;
      }

      .main-layout {
        min-height: 0;
        display: grid;
        grid-template-columns: 2.2fr 1fr;
        gap: 15px;
      }

      .tracker-panel,
      .side-panel {
        min-width: 0;
        min-height: 0;
      }

      .tracker-panel {
        overflow: hidden;
      }

      .side-panel {
        display: grid;
        grid-template-rows: auto auto minmax(0, 1fr);
        gap: 10px;
        overflow: hidden;
      }

      .comparison-panel,
      .controls-panel,
      .reporting-panel {
        min-height: 0;
        overflow: auto;
      }

      .presence-panel {
        min-height: 0;
        overflow: hidden;
      }

      .tracker-panel .shiny-plot-output,
      .presence-panel .shiny-plot-output {
        width: 100% !important;
      }

      .comparison-panel table {
        width: 100%;
      }

      .app-header h2 {
        margin: 5px 0;
      }
    "))
  ),

  div(
    class = "app-header",
    uiOutput("app_title")
  ),

  div(
    class = "main-layout",

    div(
      class = "tracker-panel",
      plotOutput("tracker_plot", height = "600px")
    ),

    div(
      class = "side-panel",

      div(
        class = "comparison-panel",
        tableOutput("comparison_table")
      ),

      div(
        class = "controls-panel",
        h4("Navigation / controls")
      ),

      div(
        class = "reporting-panel",
        h4("Issue reporting")
      )
    )
  ),

  div(
    class = "presence-panel",
    plotOutput("presence_plot", height = "160px")
  )
)

server <- function(input, output, session) {
  target_sampling_fps <- 8  # Temporary value for testing

  output$app_title <- renderUI({
    frame <- jsonlite::fromJSON(
      frame_json,
      simplifyVector = FALSE
    )

    titlePanel(
      sprintf(
        "Tracker Inspector - frame %s @ %s ms",
        frame$frame_index,
        frame$timestamp_ms
      )
    )
  })

  output$tracker_plot <- renderPlot({
    draw_frame(frame_json)    
  }, res = 96)

  output$presence_plot <- renderPlot({
    draw_presence_timeline(
      frame_json,
      target_sampling_fps = target_sampling_fps,
      window = 10
    )
  }, res = 96)

  output$comparison_table <- renderTable(
    {
      result <- calculate_detection_track_comparisons(
        frame_json,
        previous_frame_json
      )

      as.data.frame(result, stringsAsFactors = FALSE)
    },
    rownames = FALSE
  )
}

# Run with: Rscript shiny.R data.jsonl
args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop("Usage: Rscript shiny.R <data.jsonl>")
}

jsonl_path <- args[[1]]

if (!file.exists(jsonl_path)) {
  stop("File not found: ", jsonl_path)
}

records <- read_jsonl(jsonl_path)

message("Loaded ", length(records), " JSONL records from: ", jsonl_path)

shinyApp(ui = ui, server = server)
