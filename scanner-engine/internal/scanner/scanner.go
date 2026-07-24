package scanner

import (
	"fmt"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/validation"
	"net"
	"sync"
	"time"
)

var scanPortFunc = scanPort

// Scan runs a TCP connect scan
func Scan(config models.ScanConfig) (models.ScanResult, error) {
	if err := validation.ValidateScanConfig(config); err != nil {
		return models.ScanResult{}, fmt.Errorf(
			"invalid scan configuration: %w",
			err,
		)
	}

	validatedTarget, err := validation.ValidateTarget(
		config.Target,
		config.AllowPrivateTargets,
		config.AllowedTargets,
	)
	if err != nil {
		return models.ScanResult{}, fmt.Errorf("invalid target: %w", err)
	}

	startTime := time.Now()
	portCount := config.EndPort - config.StartPort + 1
	result := models.ScanResult{
		Target:    config.Target,
		StartPort: config.StartPort,
		EndPort:   config.EndPort,
		Results: make([]models.PortResult,
			0,
			portCount*len(validatedTarget.IPs)),
	}

	var wg sync.WaitGroup
	var mu sync.Mutex
	sem := make(chan struct{}, config.MaxConcurrentPorts)

	for _, ip := range validatedTarget.IPs {
		targetIP := ip.String()

		for port := config.StartPort; port <= config.EndPort; port++ {
			sem <- struct{}{}
			wg.Add(1)

			go func(target string, port int) {
				defer wg.Done()
				defer func() {
					<-sem
				}()

				portResult := scanPortFunc(target, port, config.Timeout)

				mu.Lock()
				result.Results = append(result.Results, portResult)
				mu.Unlock()
			}(targetIP, port)
		}
	}

	wg.Wait()
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
