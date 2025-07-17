#!/usr/bin/env -S make -f
# Demonstrating polyglots using R
# Part of the `compose.mk` repo. This file runs as part of the test-suite.  
# See also: http://robot-wranglers.github.io/compose.mk/demos/polyglots
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

# Creates the sine_plot.R target, with env-variable pass-through
$(call polyglot.import, def=sine_plot.R \
	local_img=RBase entrypoint=Rscript env=output_file)

# Runs rscript on the polyglot, then previews output.
__main__: sine_plot.R io.preview.img/${output_file}