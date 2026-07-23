package validation

import (
	"errors"
	"fmt"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"strings"
)

const (
	MinimumPort         = 1
	MaximumPort         = 65535
	MaximumPorts        = 1000
	MaximumTargetLength = 253
)

// ValidateScanConfig validates the complete scanner configuration.
func ValidateScanConfig(config models.ScanConfig) error {
	if err := ValidateTarget(config.Target); err != nil {
		return err
	}

	if err := ValidatePortRange(config.StartPort, config.EndPort); err != nil {
		return err
	}

	if config.Timeout <= 0 {
		return errors.New("scan timeout must be greater than zero")
	}
	return nil
}

// ValidateTarget performs basic target validation.
// Need to be improved.
func ValidateTarget(target string) error {
	target = strings.TrimSpace(target)

	if target == "" {
		return errors.New("target cannot be empty")
	}

	if len(target) > MaximumTargetLength {
		return fmt.Errorf(
			"target cannot exceed %d characters",
			MaximumTargetLength,
		)
	}

	if strings.ContainsAny(target, " \t\r\n") {
		return errors.New("target cannot contain whitespace")
	}

	return nil
}

// Validates the beginning and end of a TCP port range.
func ValidatePortRange(startPort, endPort int) error {
	if startPort < MinimumPort || startPort > MaximumPort {
		return fmt.Errorf(
			"start port must be between %d and %d",
			MinimumPort,
			MaximumPort,
		)
	}

	if endPort < MinimumPort || endPort > MaximumPort {
		return fmt.Errorf(
			"end port must be between %d and %d",
			MinimumPort,
			MaximumPort,
		)
	}

	if startPort > endPort {
		return errors.New("start port cannot be greater than end port")
	}

	portCount := endPort - startPort + 1

	if portCount > MaximumPorts {
		return fmt.Errorf(
			"scan contains %d ports; maximum allowed is %d",
			portCount,
			MaximumPorts,
		)
	}

	return nil
}
