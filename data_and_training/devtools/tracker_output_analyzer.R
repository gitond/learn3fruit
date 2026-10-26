#!/usr/bin/env Rscript

library(shiny)
library(ggplot2)
library(jsonlite)

read_jsonl <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
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

      data.frame(
        x = vapply(track_history, function(r) r$center$centerX, numeric(1)),
        y = vapply(track_history, function(r) r$center$centerY, numeric(1)),
        instanceId = track$instanceId,
        order = seq_along(track_history)
      )
    })
  )

  # Build segments from each historical point to the next.
  arrows <- do.call(
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
        instanceId = track_history$instanceId[-nrow(track_history)]
      )
    })
  )

  ggplot(
    history,
    aes(x = x, y = y, color = instanceId)
  ) +
    # Arrows connecting consecutive historical positions.
    geom_segment(
      data = arrows,
      aes(
        x = x,
        y = y,
        xend = xend,
        yend = yend,
        color = instanceId
      ),
      arrow = grid::arrow(
        length = grid::unit(0.12, "inches"),
        type = "closed"
      ),
      linewidth = 0.7,
      inherit.aes = FALSE
    ) +
    # Points at each historical position.
    geom_point(size = 3) +
    scale_color_discrete(name = "Track ID") +
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

ui <- fluidPage(
  titlePanel("Tracker Inspector — prototype"),
  plotOutput("tracker_plot", height = "600px")
)

server <- function(input, output, session) {
  output$tracker_plot <- renderPlot({
    draw_frame('{"record_type":"frame","frame_index":96,"timestamp_ms":19182,"detections":{"detections":[]},"tracker_state":{"timestamp":19182,"tracks":[{"instanceId":"#10","status":"TEMPORARILY_MISSING","center":{"centerX":398.5,"centerY":178},"boundingBox":{"originX":295,"originY":120,"width":207,"height":116,"angle":0},"velocity":{"vx":0.11424631860776438,"vy":0.018510231401797667},"history":[{"timestamp":18057,"category":"bowl","detectionConfidence":0.514365553855896,"boundingBox":{"originX":211,"originY":104,"width":213,"height":123,"angle":0},"center":{"centerX":317.5,"centerY":165.5}},{"timestamp":18182,"category":"bowl","detectionConfidence":0.5371545553207397,"boundingBox":{"originX":214,"originY":106,"width":211,"height":121,"angle":0},"center":{"centerX":319.5,"centerY":166.5}},{"timestamp":18307,"category":"bowl","detectionConfidence":0.5508236885070801,"boundingBox":{"originX":218,"originY":111,"width":210,"height":119,"angle":0},"center":{"centerX":323,"centerY":170.5}},{"timestamp":18433,"category":"bowl","detectionConfidence":0.5722896456718445,"boundingBox":{"originX":238,"originY":112,"width":226,"height":119,"angle":0},"center":{"centerX":351,"centerY":171.5}},{"timestamp":18682,"category":"bowl","detectionConfidence":0.5244160890579224,"boundingBox":{"originX":295,"originY":120,"width":207,"height":116,"angle":0},"center":{"centerX":398.5,"centerY":178}}],"categoryHistory":{},"currentCategory":"bowl","lastDetectionConfidence":0.5244160890579224,"hasBeenConfirmed":true,"createdAt":16181,"updatedAt":18682,"consecutiveHits":0,"consecutiveMisses":4},{"instanceId":"#11","status":"TEMPORARILY_MISSING","center":{"centerX":207,"centerY":165.5},"boundingBox":{"originX":76,"originY":113,"width":262,"height":105,"angle":0},"velocity":{"vx":0,"vy":0},"history":[{"timestamp":18931,"category":"bowl","detectionConfidence":0.3983275592327118,"boundingBox":{"originX":76,"originY":113,"width":262,"height":105,"angle":0},"center":{"centerX":207,"centerY":165.5}}],"categoryHistory":{},"currentCategory":"bowl","lastDetectionConfidence":0.3983275592327118,"hasBeenConfirmed":false,"createdAt":18931,"updatedAt":18931,"consecutiveHits":0,"consecutiveMisses":2}]}}')
  }, res = 96)
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
