FROM alpine
RUN apk add -q --update --no-cache coreutils build-base bash
ADD compose.mk /usr/local/bin