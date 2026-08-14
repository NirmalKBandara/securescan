#!/usr/bin/env sh
set -eu

gateway_url="${SECURESCAN_GATEWAY_URL:-https://localhost:8243/securescan/v1}"
access_token="${SECURESCAN_GATEWAY_TOKEN:-}"

if [ -z "$access_token" ]; then
    echo "SECURESCAN_GATEWAY_TOKEN is required" >&2
    exit 2
fi

status_without_token="$(curl --insecure --silent --output /dev/null \
    --write-out '%{http_code}' "$gateway_url/api/v1/scans?pageSize=1")"
status_with_invalid_token="$(curl --insecure --silent --output /dev/null \
    --write-out '%{http_code}' --header 'Authorization: Bearer invalid' \
    "$gateway_url/api/v1/scans?pageSize=1")"
status_with_token="$(curl --insecure --silent --output /dev/null \
    --write-out '%{http_code}' --header "Authorization: Bearer $access_token" \
    "$gateway_url/api/v1/scans?pageSize=1")"

case "$status_without_token" in
    401|403) ;;
    *) echo "missing token was not rejected by the Gateway: HTTP $status_without_token" >&2; exit 1 ;;
esac

case "$status_with_invalid_token" in
    401|403) ;;
    *) echo "invalid token was not rejected by the Gateway: HTTP $status_with_invalid_token" >&2; exit 1 ;;
esac

if [ "$status_with_token" != "200" ]; then
    echo "valid Gateway token did not reach Ballerina successfully: HTTP $status_with_token" >&2
    exit 1
fi

echo "gateway verification passed: missing=$status_without_token invalid=$status_with_invalid_token valid=$status_with_token"
