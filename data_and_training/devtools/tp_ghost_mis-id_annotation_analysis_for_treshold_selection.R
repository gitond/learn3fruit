# for loading data into analysis
library(jsonlite)

# For data manipulation
suppressPackageStartupMessages(library(dplyr)) # <- Don't print warning on import
library(tidyr)

# For plotting & rendering
library(ggplot2)
library(scales)
library(knitr)
input_file <- "results_annotated.jsonl"

raw_data <- stream_in(file(input_file), verbose = FALSE)

length(raw_data)
detections <- raw_data %>%
  mutate(
    frame = image
  ) %>%
  select(frame, detections) %>%
  unnest(detections) %>%
  mutate(
    annotation = factor(
      annotation,
      levels = c("TP", "MIS-ID", "GHOST")
    )
  ) %>%
  select(
    frame,
    name,
    score,
    annotation
  ) %>%
  rename(
    class = name
  )

print(as.data.frame(head(detections)), row.names = FALSE)
score_breaks <- seq(0, 1, by = 0.05)

score_range_stats <- detections %>%
  mutate(
    score_range = cut(
      score,
      breaks = score_breaks,
      include.lowest = TRUE,
      right = FALSE
    )
  ) %>%
  group_by(score_range) %>%
  summarise(
    `n(TP)` = sum(annotation == "TP"),
    `n(MIS-ID)` = sum(annotation == "MIS-ID"),
    `n(GHOST)` = sum(annotation == "GHOST"),
    TP_rate = sum(annotation == "TP") / n(),
    .groups = "drop"
  )

print(score_range_stats %>%
    mutate(
      TP_rate = percent(TP_rate, accuracy = 0.1)
    ) %>%
  as.data.frame(row.names = NULL),
  row.names = FALSE
)
highest_score <- max(detections$score, na.rm = TRUE)
# ceiling would round up to an integer. We want to round up to the next heundredth 
# (seuraavaan sadasosaan)
threshold_max <- ceiling(highest_score * 100) / 100 + 0.01
thresholds <- seq(0.10, threshold_max, by = 0.01)

all_tp <- sum(detections$annotation == "TP")

threshold_stats <- lapply(thresholds, function(t) {

  accepted <- detections %>%
    filter(score >= t)

  n_accepted <- nrow(accepted)

  n_tp <- sum(accepted$annotation == "TP")
  n_mis_id <- sum(accepted$annotation == "MIS-ID")
  n_ghost <- sum(accepted$annotation == "GHOST")

  precision <- if (n_accepted > 0) {
    n_tp / n_accepted
  } else {
    NA_real_
  }

  tp_retention <- if (all_tp > 0) {
    n_tp / all_tp
  } else {
    NA_real_
  }

  data.frame(
    threshold = t,
    n_accepted = n_accepted,
    n_tp = n_tp,
    n_mis_id = n_mis_id,
    n_ghost = n_ghost,
    precision = precision,
    tp_retention = tp_retention
  )
}) %>%
  bind_rows()

threshold_stats %>%
  transmute(
    threshold = sprintf("%.2f", threshold),
    `n(accepted)` = n_accepted,
    `n(TP)` = n_tp,
    `n(MIS-ID)` = n_mis_id,
    `n(GHOST)` = n_ghost,
    `precision` = percent(precision, accuracy = 0.1)
  )
threshold_stats %>%
  transmute(
    threshold = sprintf("%.2f", threshold),
    precision = percent(precision, accuracy = 0.1),
    `portion of all TPs accepted` =
      percent(tp_retention, accuracy = 0.1)
  )
class_medians <- detections %>%
  group_by(class) %>%
  summarise(
    `median(TP)` =
      if (any(annotation == "TP"))
        median(score[annotation == "TP"])
      else
        NA_real_,

    `median(MIS-ID)` =
      if (any(annotation == "MIS-ID"))
        median(score[annotation == "MIS-ID"])
      else
        NA_real_,

    `median(GHOST)` =
      if (any(annotation == "GHOST"))
        median(score[annotation == "GHOST"])
      else
        NA_real_,

    .groups = "drop"
  )

print(as.data.frame(class_medians), row.names = FALSE)
class_median_means <- data.frame(
  outcome = c("TP", "MIS-ID", "GHOST"),
  mean_of_class_medians = c(
    mean(class_medians$`median(TP)`, na.rm = TRUE),
    mean(class_medians$`median(MIS-ID)`, na.rm = TRUE),
    mean(class_medians$`median(GHOST)`, na.rm = TRUE)
  )
)

class_median_means
all_frames <- raw_data %>%
  transmute(frame = image)

frame_stats <- all_frames %>%
  left_join(
    detections %>%
      group_by(frame) %>%
      summarise(
        `n(TP)` = sum(annotation == "TP"),
        `n(MIS-ID)` = sum(annotation == "MIS-ID"),
        `n(GHOST)` = sum(annotation == "GHOST"),
        n_detections = n(),
        .groups = "drop"
      ),
    by = "frame"
  ) %>%
  mutate(
    `n(TP)` = coalesce(`n(TP)`, 0L),
    `n(MIS-ID)` = coalesce(`n(MIS-ID)`, 0L),
    `n(GHOST)` = coalesce(`n(GHOST)`, 0L),
    n_detections = coalesce(n_detections, 0L),

    `TP rate` = if_else(
      n_detections > 0,
      `n(TP)` / n_detections,
      NA_real_
    )
  ) %>%
  select(
    frame,
    `n(TP)`,
    `n(MIS-ID)`,
    `n(GHOST)`,
    `TP rate`
  )

frame_stats %>%
  mutate(
    `TP rate` = ifelse(
      is.na(`TP rate`),
      "N/A",
      percent(`TP rate`, accuracy = 0.1)
    )
  )
overall_score_stats <- detections %>%
  group_by(annotation) %>%
  summarise(
    n = n(),
    mean = mean(score),
    median = median(score),
    p10 = quantile(score, 0.10),
    p90 = quantile(score, 0.90),
    .groups = "drop"
  ) %>%
  arrange(
    factor(annotation, levels = c("TP", "MIS-ID", "GHOST"))
  )

print(as.data.frame(overall_score_stats), row.names = FALSE)
ggplot(
  detections,
  aes(
    x = score,
    fill = annotation
  )
) +
  geom_histogram(
    aes(y = after_stat(count)),
    bins = 40,
    position = "stack",
    colour = "black",
    linewidth = 0.3
  ) +
  scale_x_continuous(
    labels = percent
  ) +
  labs(
    title = "Detection score distributions",
    x = "NN confidence score",
    y = "Frequency",
    fill = "Outcome"
  ) +
  theme_minimal()
ggplot(
  threshold_stats,
  aes(
    x = threshold,
    y = precision
  )
) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.2) +
  scale_x_continuous(
    limits = c(0.10, threshold_max),
    labels = percent
  ) +
  scale_y_continuous(
    labels = percent
  ) +
  coord_cartesian(ylim = c(0, 1)) +
  labs(
    title = "Precision vs confidence threshold",
    x = "Confidence threshold",
    y = "Precision"
  ) +
  theme_minimal()
ggplot(
  threshold_stats,
  aes(
    x = threshold,
    y = tp_retention
  )
) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 1.2) +
  scale_x_continuous(
    limits = c(0.10, threshold_max),
    labels = percent
  ) +
  scale_y_continuous(
    limits = c(0, 1),
    labels = percent
  ) +
  labs(
    title = "TP retention vs confidence threshold",
    x = "Confidence threshold",
    y = "Portion of all TPs accepted"
  ) +
  theme_minimal()
