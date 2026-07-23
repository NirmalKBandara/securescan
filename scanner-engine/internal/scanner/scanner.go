package scanner

import (
	"fmt"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/validation"
	"net"
	"time"
)

// Scan runs a TCP connect scan
func Scan(config models.ScanConfig) (models.ScanResult, error) {
	if err := validation.ValidateScanConfig(config); err != nil {
		return models.ScanResult{}, fmt.Errorf(
			"invalid scan configuration: %w",
			err,
		)
	}
	startTime := time.Now()
	result := models.ScanResult{
		Target:    config.Target,
		StartPort: config.StartPort,
		EndPort:   config.EndPort,
		Results: make([]models.PortResult,
			0,
			config.EndPort-config.StartPort+1),
	}

	for port := config.StartPort; port <= config.EndPort; port++ {
		portResult := scanPort(config.Target, port, config.Timeout)
		result.Results = append(result.Results, portResult)
	}

	result.Duration = time.Since(startTime)
	return result, nil
}

// Establish a complete TCP connection to one port.
func scanPort(
	target string,
	port int,
	timeout time.Duration,
) models.PortResult {
	address := net.JoinHostPort(target, fmt.Sprintf("%d", port))
	connection, err := net.DialTimeout("tcp", address, timeout)

	if err != nil {
		return models.PortResult{
			Port:  port,
			State: "closed",
			Error: err.Error(),
		}
	}

	if err := connection.Close(); err != nil {
		return models.PortResult{
			Port:  port,
			State: "open",
			Error: fmt.Sprintf("failed to close connection: %v", err),
		}
	}

	return models.PortResult{
		Port:  port,
		State: "open",
	}
}
