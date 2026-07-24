package validation

import "fmt"

// Validates the beginning and end of a TCP port range.
func ValidatePortRange(
	startPort int,
	endPort int,
	maxPortsPerScan int,
) error {
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
		return fmt.Errorf("start port cannot be greater than end port")
	}

	portCount := endPort - startPort + 1

	if portCount > maxPortsPerScan {
		return fmt.Errorf(
			"requested %d ports; maximum allowed is %d",
			portCount,
			maxPortsPerScan,
		)
	}

	return nil
}
