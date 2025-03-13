# FROM alpine
# RUN apk add -q --update --no-cache coreutils alpine-sdk bash procps-ng
FROM ${IMG_DEBIAN_BASE:-debian:bookworm}
RUN apt-get update -qq && apt-get install -y make procps
RUN echo Building container spec from external Dockerfile
