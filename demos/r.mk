#!/usr/bin/env -S make -f
#
# r.mk: Polyglots using R
#
# USAGE: ./demos/r.mk

include compose.mk

export output_file=.tmp.png

# Look, it's a base image with small extras for R 
define Dockerfile.RBase
FROM r-base:4.3.1
RUN R -e "install.packages('ggplot2', repos='https://cran.rstudio.com/')"
endef

# Look, it's a script written in R 
define sine_plot.R
library(ggplot2)
x <- seq(0, 2 * pi, length.out = 1000)
df <- data.frame(x = x, y = sin(x))
outfile <- Sys.getenv("output_file")
png(filename = outfile, width = 400, height = 200)
ggplot(df, aes(x = x, y = y)) +
  geom_line(linewidth = 1, color = "blue") +
  ggtitle("Sine Wave") +
  xlab("x") + ylab("sin(x)") +
  theme_minimal()
endef

# A code-object bound to the locally-built image (compose.mk:RBase is the tag
# Dockerfile.build/RBase produces), with env-variable pass-through.
$(call code, def=sine_plot.R img=compose.mk:RBase entrypoint=Rscript env=output_file)

# Build the image, run rscript on the polyglot, then preview output.
__main__: Dockerfile.build/RBase sine_plot.R io.preview.img/${output_file}
