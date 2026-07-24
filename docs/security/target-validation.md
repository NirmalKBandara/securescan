# Target Validation And Scan Safety

SecureScan validates every scan target before opening network connections.

## Validation Flow

1. Trim and check the target string.
2. Reject empty targets, overly long targets and whitespace.
3. If the target is an IPv4 or IPv6 address, classify the address directly.
4. If the target is a hostname, validate strict hostname syntax.
5. Resolve valid hostnames to IP addresses.
6. Reject the target if any resolved IP address is unsafe.
7. Scan the validated IP addresses, not the original hostname.
8. Enforce maximum port count, per-port timeout and concurrent scan limits.

## Blocked Address Types

SecureScan blocks these address types by default:

* Private IP ranges, such as `10.0.0.0/8`, `172.16.0.0/12` and `192.168.0.0/16`
* Loopback addresses, such as `127.0.0.0/8` and `::1`
* Link-local addresses, such as `169.254.0.0/16` and `fe80::/10`
* Multicast addresses, such as `224.0.0.0/4` and `ff00::/8`
* Unspecified addresses, such as `0.0.0.0` and `::`
* Cloud metadata addresses, such as `169.254.169.254` and `fd00:ec2::254`

Private targets may be enabled for development with `ALLOW_PRIVATE_TARGETS=true`.
Cloud metadata, loopback, link-local, multicast and unspecified addresses remain
blocked because they are not safe remote scan targets.

## Development Allowlist

`ALLOWED_TARGETS` accepts a comma-separated list of exact hostnames or IP
addresses. When configured, SecureScan rejects targets that do not match the
allowlist before DNS resolution or scanning.

## SSRF Protection

Server-Side Request Forgery happens when user-controlled input causes a server
to connect to unintended internal resources. For a scanner, this risk is direct:
the target string controls where the scanner process connects.

These controls reduce SSRF and accidental misuse by preventing the scanner from
being used as a proxy into private networks, localhost-only services, link-local
services or cloud metadata endpoints.
