package validation

import (
	"errors"
	"fmt"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"net"
	"net/netip"
	"strings"
)

const (
	MinimumPort            = 1
	MaximumPort            = 65535
	MaximumPorts           = 1000
	MaximumTargetLength    = 253
	MaximumTargetAddresses = 16
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

// ValidatePinnedTarget validates an upstream-authorized address set. It never
// resolves target: callers can safely use the returned IPs without allowing a
// later DNS answer to change the dial destination.
func ValidatePinnedTarget(
	target string,
	authorizedAddresses []string,
	allowPrivate bool,
	allowedTargets []string,
) (ValidatedTarget, error) {
	target = strings.TrimSpace(target)
	if err := validateTargetIdentity(target, allowedTargets); err != nil {
		return ValidatedTarget{}, err
	}
	if len(authorizedAddresses) == 0 {
		return ValidatedTarget{}, newTargetError(
			BlockedTarget,
			"authorized address set is required",
		)
	}
	if len(authorizedAddresses) > MaximumTargetAddresses {
		return ValidatedTarget{}, newTargetErrorf(
			BlockedTarget, "authorized address set cannot exceed %d addresses", MaximumTargetAddresses,
		)
	}

	ips := make([]net.IP, 0, len(authorizedAddresses))
	seen := make(map[string]struct{}, len(authorizedAddresses))
	for _, raw := range authorizedAddresses {
		if raw != strings.TrimSpace(raw) {
			return ValidatedTarget{}, newTargetError(InvalidTarget, "authorized address is not canonical")
		}
		ip := net.ParseIP(raw)
		if ip == nil {
			return ValidatedTarget{}, newTargetErrorf(InvalidTarget, "invalid authorized address %q", raw)
		}
		canonical := ip.String()
		if isBlockedIP(ip, allowPrivate) {
			return ValidatedTarget{}, newTargetErrorf(BlockedTarget, "authorized address %s is blocked", raw)
		}
		if _, duplicate := seen[canonical]; duplicate {
			return ValidatedTarget{}, newTargetError(InvalidTarget, "authorized address set contains duplicates")
		}
		seen[canonical] = struct{}{}
		ips = append(ips, ip)
	}

	if targetIP := net.ParseIP(target); targetIP != nil {
		if len(ips) != 1 || !targetIP.Equal(ips[0]) {
			return ValidatedTarget{}, newTargetError(BlockedTarget, "authorized address set does not match target IP")
		}
	} else if err := validateHostname(target); err != nil {
		return ValidatedTarget{}, newTargetError(InvalidTarget, err.Error())
	}

	return ValidatedTarget{Original: target, IPs: ips}, nil
}

// VerifyCurrentResolution requires DNS to still return exactly the pinned set.
// The subsequent scan must use pinned.IPs and must not resolve the hostname.
func VerifyCurrentResolution(pinned ValidatedTarget) error {
	if net.ParseIP(pinned.Original) != nil {
		return nil
	}
	current, err := lookupIP(pinned.Original)
	if err != nil {
		return newTargetErrorf(InvalidTarget, "failed to resolve target hostname: %v", err)
	}
	if !sameIPSet(pinned.IPs, current) {
		return newTargetError(BlockedTarget, "authorized address set does not match current DNS resolution")
	}
	return nil
}

func sameIPSet(left, right []net.IP) bool {
	if len(left) != len(right) {
		return false
	}
	values := make(map[string]struct{}, len(left))
	for _, ip := range left {
		if ip == nil {
			return false
		}
		values[ip.String()] = struct{}{}
	}
	if len(values) != len(left) {
		return false
	}
	current := make(map[string]struct{}, len(right))
	for _, ip := range right {
		if ip == nil {
			return false
		}
		canonical := ip.String()
		if _, found := values[canonical]; !found {
			return false
		}
		current[canonical] = struct{}{}
	}
	return len(current) == len(right)
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

	if err := validateTargetIdentity(target, allowedTargets); err != nil {
		return ValidatedTarget{}, err
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
	if len(ips) > MaximumTargetAddresses {
		return ValidatedTarget{}, newTargetErrorf(
			BlockedTarget, "target hostname cannot resolve to more than %d addresses", MaximumTargetAddresses,
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

func validateTargetIdentity(target string, allowedTargets []string) error {
	if target == "" {
		return newTargetError(
			InvalidTarget,
			"target cannot be empty",
		)
	}

	if len(target) > MaximumTargetLength {
		return newTargetErrorf(
			InvalidTarget,
			"target cannot exceed %d characters",
			MaximumTargetLength,
		)
	}

	if strings.ContainsAny(target, " \t\r\n") {
		return newTargetError(
			InvalidTarget,
			"target cannot contain whitespace",
		)
	}

	if !isAllowedTarget(target, allowedTargets) {
		return newTargetError(
			BlockedTarget,
			"target is not in the configured allowlist",
		)
	}

	return nil
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
	address, valid := netip.AddrFromSlice(ip)
	if !valid {
		return true
	}
	address = address.Unmap()
	ip = net.IP(address.AsSlice())

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

	if isSpecialUseIP(address) {
		return true
	}

	if ip.IsPrivate() && !allowPrivate {
		return true
	}
	return false
}

var blockedSpecialUsePrefixes = []netip.Prefix{
	netip.MustParsePrefix("100.64.0.0/10"),   // shared address space (CGNAT)
	netip.MustParsePrefix("192.0.0.0/24"),    // IETF protocol assignments
	netip.MustParsePrefix("192.0.2.0/24"),    // documentation
	netip.MustParsePrefix("198.18.0.0/15"),   // benchmarking
	netip.MustParsePrefix("198.51.100.0/24"), // documentation
	netip.MustParsePrefix("203.0.113.0/24"),  // documentation
	netip.MustParsePrefix("240.0.0.0/4"),     // reserved
	netip.MustParsePrefix("100::/64"),        // discard-only
	netip.MustParsePrefix("2001:2::/48"),     // benchmarking
	netip.MustParsePrefix("2001:10::/28"),    // deprecated ORCHID
	netip.MustParsePrefix("2001:20::/28"),    // ORCHIDv2
	netip.MustParsePrefix("2001:db8::/32"),   // documentation
}

func isSpecialUseIP(address netip.Addr) bool {
	for _, prefix := range blockedSpecialUsePrefixes {
		if prefix.Contains(address) {
			return true
		}
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
