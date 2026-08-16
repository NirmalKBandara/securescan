package scanner

import (
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

func TestScanDialsEveryPinnedAddressAndPreservesOriginalTarget(t *testing.T) {
	original := scanPortFunc
	t.Cleanup(func() { scanPortFunc = original })
	var mu sync.Mutex
	var dialed []string
	scanPortFunc = func(target string, port int, timeout time.Duration) models.PortResult {
		mu.Lock()
		dialed = append(dialed, target)
		mu.Unlock()
		return models.PortResult{Address: target, Port: port, State: "closed"}
	}

	result, err := Scan(models.ScanConfig{
		Target: "scan.example", AuthorizedAddresses: []string{"8.8.8.8", "1.1.1.1"},
		StartPort: 443, EndPort: 443, Timeout: time.Second,
		MaxPortsPerScan: 10, MaxConcurrentPorts: 2,
	})
	if err != nil {
		t.Fatalf("scan pinned targets: %v", err)
	}
	sort.Strings(dialed)
	if len(dialed) != 2 || dialed[0] != "1.1.1.1" || dialed[1] != "8.8.8.8" {
		t.Fatalf("expected only pinned addresses to be dialed, got %v", dialed)
	}
	if result.Target != "scan.example" {
		t.Fatalf("expected original target attribution, got %q", result.Target)
	}
}
