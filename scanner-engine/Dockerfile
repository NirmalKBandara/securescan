# syntax=docker/dockerfile:1

FROM golang:1.26-alpine AS build

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/securescan-scanner ./cmd/server

FROM alpine:3.22

RUN apk add --no-cache ca-certificates \
    && addgroup -S securescan \
    && adduser -S -G securescan -H -s /sbin/nologin securescan

COPY --from=build /out/securescan-scanner /usr/local/bin/securescan-scanner

USER securescan
EXPOSE 8081

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget --quiet --tries=1 --spider http://127.0.0.1:8081/health || exit 1

ENTRYPOINT ["/usr/local/bin/securescan-scanner"]
