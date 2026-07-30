package validation

import (
	"errors"
	"fmt"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"net"
	"strings"
)

const (
	MinimumPort         = 1
	MaximumPort         = 65535
	MaximumPorts        = 1000
	MaximumTargetLength = 253
)

type TargetErrorKind string

const (
	InvalidTarget TargetErrorKind = "invalid"
	BlockedTarget TargetErrorKind = "blocked"
)

type TargetError struct {
	Kind    TargetErrorKind
	Message string
}

func (err *TargetError) Error() string {
	return err.Message
}

func newTargetError(kind TargetErrorKind, message string) error {
	return &TargetError{Kind: kind, Message: message}
}

func newTargetErrorf(kind TargetErrorKind, format string, args ...any) error {
	return newTargetError(kind, fmt.Sprintf(format, args...))
}

func IsBlockedTargetError(err error) bool {
	var targetErr *TargetError
	return errors.As(err, &targetErr) && targetErr.Kind == BlockedTarget
}

type ValidatedTarget struct {
	Original string
	IPs      []net.IP
}

var lookupIP = net.LookupIP

// Validates scan limits that do not require DNS.
func ValidateScanConfig(config models.ScanConfig) error {
	if strings.TrimSpace(config.Target) == "" {
		return errors.New("target cannot be empty")
	}

	if config.MaxPortsPerScan <= 0 {
		return errors.New("maximum ports per scan must be greater than zero")
	}

	if config.MaxConcurrentPorts <= 0 {
		return errors.New("maximum concurrent ports must be greater than zero")
	}

	if err := ValidatePortRange(
		config.StartPort,
		config.EndPort,
		config.MaxPortsPerScan,
	); err != nil {
		return err
	}

	if config.Timeout <= 0 {
		return errors.New("scan timeout must be greater than zero")
	}
	return nil
}

// Resolves and validates a scan target before any connection.
func ValidateTarget(
	target string,
	allowPrivate bool,
	allowedTargets []string,
) (ValidatedTarget, error) {
	target = strings.TrimSpace(target)

	if target == "" {
		return ValidatedTarget{}, newTargetError(
			InvalidTarget,
			"target cannot be empty",
		)
	}

	if len(target) > MaximumTargetLength {
		return ValidatedTarget{}, newTargetErrorf(
			InvalidTarget,
			"target cannot exceed %d characters",
			MaximumTargetLength,
		)
	}

	if strings.ContainsAny(target, " \t\r\n") {
		return ValidatedTarget{}, newTargetError(
			InvalidTarget,
			"target cannot contain whitespace",
		)
	}

	if !isAllowedTarget(target, allowedTargets) {
		return ValidatedTarget{}, newTargetError(
			BlockedTarget,
			"target is not in the configured allowlist",
		)
	}

	if ip := net.ParseIP(target); ip != nil {
		if isBlockedIP(ip, allowPrivate) {
			return ValidatedTarget{}, newTargetErrorf(
				BlockedTarget,
				"target IP %s is blocked",
				ip.String(),
			)
		}

		return ValidatedTarget{
			Original: target,
			IPs:      []net.IP{ip},
		}, nil
	}

	if err := validateHostname(target); err != nil {
		return ValidatedTarget{}, newTargetError(InvalidTarget, err.Error())
	}

	ips, err := lookupIP(target)
	if err != nil {
		return ValidatedTarget{}, newTargetErrorf(
			InvalidTarget,
			"failed to resolve target hostname: %v",
			err,
		)
	}

	if len(ips) == 0 {
		return ValidatedTarget{}, newTargetError(
			InvalidTarget,
			"target hostname resolved to no IP addresses",
		)
	}

	for _, ip := range ips {
		if isBlockedIP(ip, allowPrivate) {
			return ValidatedTarget{}, newTargetErrorf(
				BlockedTarget,
				"target hostname resolved to blocked IP %s",
				ip.String(),
			)
		}
	}

	return ValidatedTarget{
		Original: target,
		IPs:      ips,
	}, nil
}

func isAllowedTarget(target string, allowedTargets []string) bool {
	if len(allowedTargets) == 0 {
		return true
	}
	normalizedTarget := strings.ToLower(strings.TrimSuffix(target, "."))

	for _, allowed := range allowedTargets {
		normalizedAllowed := strings.ToLower(strings.TrimSuffix(strings.TrimSpace(allowed), "."))
		if normalizedTarget == normalizedAllowed {
			return true
		}
	}

	return false
}

func isBlockedIP(ip net.IP, allowPrivate bool) bool {
	if ip.IsUnspecified() {
		return true
	}

	if ip.IsLoopback() {
		return true
	}

	if ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() {
		return true
	}

	if ip.IsMulticast() {
		return true
	}

	if isCloudMetadataIP(ip) {
		return true
	}

	if ip.IsPrivate() && !allowPrivate {
		return true
	}
	return false
}

func isCloudMetadataIP(ip net.IP) bool {
	blocked := []string{
		"169.254.169.254",
		"fd00:ec2::254",
	}

	for _, raw := range blocked {
		if ip.Equal(net.ParseIP(raw)) {
			return true
		}
	}
	return false
}

func validateHostname(host string) error {
	if host == "" || len(host) > MaximumTargetLength {
		return errors.New("invalid hostname length")
	}

	if strings.ContainsAny(host, " /:\\") {
		return errors.New("hostname cannot contain spaces, slashes, colons, or backslashes")
	}

	labels := strings.Split(host, ".")
	for _, label := range labels {
		if label == "" || len(label) > 63 {
			return errors.New("invalid hostname label")
		}

		if strings.HasPrefix(label, "-") || strings.HasSuffix(label, "-") {
			return errors.New("hostname label cannot start or end with hyphen")
		}

		for _, r := range label {
			if !isHostnameRune(r) {
				return errors.New("hostname contains invalid character")
			}
		}
	}
	return nil
}

func isHostnameRune(r rune) bool {
	return (r >= 'a' && r <= 'z') ||
		(r >= 'A' && r <= 'Z') ||
		(r >= '0' && r <= '9') ||
		r == '-'
}
