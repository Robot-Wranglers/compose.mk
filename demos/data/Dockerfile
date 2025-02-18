# FROM alpine
# RUN apk add --update --no-cache coreutils alpine-sdk bash procps-ng
FROM debian:bookworm
RUN apt-get update
RUN apt-get install -y make procps
RUN echo Building container spec from inlined dockerfile