package config

import (
	"testing"
	"time"
)

func TestLoadUsesSafeDefaults(t *testing.T) {
	t.Setenv("ALLOW_PRIVATE_TARGETS", "")
	t.Setenv("MAX_PORTS_PER_SCAN", "")
	t.Setenv("MAX_CONCURRENT_PORTS", "")
	t.Setenv("SCAN_TIMEOUT_MS", "")
	t.Setenv("ALLOWED_TARGETS", "")

	config, err := Load()
	if err != nil {
		t.Fatalf("expected default config to load: %v", err)
	}

	if config.AllowPrivateTargets {
		t.Fatal("expected private targets to be blocked by default")
	}

	if config.MaxPortsPerScan != defaultMaxPorts {
		t.Fatalf("expected max ports %d, got %d", defaultMaxPorts, config.MaxPortsPerScan)
	}

	if config.MaxConcurrentPorts != defaultMaxConcurrency {
		t.Fatalf(
			"expected max concurrency %d, got %d",
			defaultMaxConcurrency,
			config.MaxConcurrentPorts,
		)
	}

	if config.ScanTimeout != time.Duration(defaultScanTimeoutMS)*time.Millisecond {
		t.Fatalf("unexpected scan timeout: %s", config.ScanTimeout)
	}
}

func TestLoadRejectsInvalidValues(t *testing.T) {
	tests := []struct {
		name  string
		key   string
		value string
	}{
		{
			name:  "invalid allow private boolean",
			key:   "ALLOW_PRIVATE_TARGETS",
			value: "maybe",
		},
		{
			name:  "invalid max ports",
			key:   "MAX_PORTS_PER_SCAN",
			value: "0",
		},
		{
			name:  "invalid max concurrency",
			key:   "MAX_CONCURRENT_PORTS",
			value: "-1",
		},
		{
			name:  "invalid timeout",
			key:   "SCAN_TIMEOUT_MS",
			value: "nope",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("ALLOW_PRIVATE_TARGETS", "")
			t.Setenv("MAX_PORTS_PER_SCAN", "")
			t.Setenv("MAX_CONCURRENT_PORTS", "")
			t.Setenv("SCAN_TIMEOUT_MS", "")
			t.Setenv("ALLOWED_TARGETS", "")
			t.Setenv(test.key, test.value)

			_, err := Load()
			if err == nil {
				t.Fatal("expected invalid config to fail")
			}
		})
	}
}

func TestLoadReadsAllowlist(t *testing.T) {
	t.Setenv("ALLOW_PRIVATE_TARGETS", "")
	t.Setenv("MAX_PORTS_PER_SCAN", "")
	t.Setenv("MAX_CONCURRENT_PORTS", "")
	t.Setenv("SCAN_TIMEOUT_MS", "")
	t.Setenv("ALLOWED_TARGETS", " Scanme.Example, 8.8.8.8 ")

	config, err := Load()
	if err != nil {
		t.Fatalf("expected config to load: %v", err)
	}

	if len(config.AllowedTargets) != 2 {
		t.Fatalf("expected 2 allowlist entries, got %d", len(config.AllowedTargets))
	}

	if config.AllowedTargets[0] != "scanme.example" {
		t.Fatalf("expected lowercased allowlist entry, got %q", config.AllowedTargets[0])
	}
}
