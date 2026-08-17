# syntax=docker/dockerfile:1

FROM ballerina/ballerina-devcontainer:2201.13.4 AS build

USER root
WORKDIR /workspace
COPY . .
RUN bal build

FROM eclipse-temurin:21-jre-alpine

RUN apk add --no-cache ca-certificates \
    && addgroup -S securescan \
    && adduser -S -G securescan -H -s /sbin/nologin securescan

WORKDIR /opt/securescan
COPY --from=build /workspace/target/bin/ballerina_api.jar ./ballerina_api.jar

USER securescan
EXPOSE 9090

HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=6 \
    CMD wget --quiet --tries=1 --spider http://127.0.0.1:9090/health || exit 1

ENTRYPOINT ["java", "-jar", "/opt/securescan/ballerina_api.jar"]
