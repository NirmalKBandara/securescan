package scanner

import (
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"sync"
	"testing"
	"time"
)

func TestScanRespectsConcurrencyLimit(t *testing.T) {
	originalScanPortFunc := scanPortFunc
	t.Cleanup(func() {
		scanPortFunc = originalScanPortFunc
	})

	var mu sync.Mutex
	activeScans := 0
	maxActiveScans := 0

	scanPortFunc = func(target string, port int, timeout time.Duration) models.PortResult {
		mu.Lock()
		activeScans++
		if activeScans > maxActiveScans {
			maxActiveScans = activeScans
		}
		mu.Unlock()
		time.Sleep(10 * time.Millisecond)

		mu.Lock()
		activeScans--
		mu.Unlock()

		return models.PortResult{
			Port:  port,
			State: "closed",
		}
	}

	config := models.ScanConfig{
		Target:              "8.8.8.8",
		StartPort:           1,
		EndPort:             20,
		Timeout:             time.Second,
		AllowPrivateTargets: false,
		MaxPortsPerScan:     1000,
		MaxConcurrentPorts:  5,
	}

	result, err := Scan(config)
	if err != nil {
		t.Fatalf("expected scan to complete: %v", err)
	}

	if len(result.Results) != 20 {
		t.Fatalf("expected 20 port results, got %d", len(result.Results))
	}

	if maxActiveScans > config.MaxConcurrentPorts {
		t.Fatalf(
			"expected at most %d active scans, saw %d",
			config.MaxConcurrentPorts,
			maxActiveScans,
		)
	}
}
