library(ggplot2)
suppressPackageStartupMessages(library(dplyr))
library(tidyr)
library(scales)

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0) {
  stop("Error: Missing CSV filename parameter.\nUsage: Rscript fpsdiagram.r <filename.csv>", call. = FALSE)
}

input_filename <- args[1]

if (!file.exists(input_filename)) {
  stop(paste0("Error: File '", input_filename, "' not found."), call. = FALSE)
}

df <- read.csv(input_filename, stringsAsFactors = FALSE)
df$Timestamp <- as.POSIXct(df$Timestamp, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")

df_long <- df %>%
  pivot_longer(
    cols = c(Camera_FPS, Sampling_FPS, Inference_FPS),
    names_to = "Metric",
    values_to = "FPS"
  )

p <- ggplot(df_long, aes(x = Timestamp, y = FPS, color = Metric)) +
  geom_line(linewidth = 1) +
  geom_point(size = 2) +
  scale_x_datetime(labels = date_format("%H:%M:%S")) +
  labs(
    title = "Performance Monitoring Metrics",
    subtitle = paste("File:", input_filename),
    x = "Timestamp (UTC)",
    y = "FPS",
    color = "Metric"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    legend.position = "bottom",
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

# 1. Open a graphic window device explicitly
x11() # On macOS use quartz(), on Windows use windows()

# 2. Render plot
print(p)

# 3. Keep window open for 10 sec
while(names(dev.cur()) !='null device') Sys.sleep(1)
