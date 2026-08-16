package config

import (
	"testing"
	"time"
)

func TestLoadUsesSafeDefaults(t *testing.T) {
	t.Setenv("ALLOW_PRIVATE_TARGETS", "")
	t.Setenv("SCANNER_ISOLATED_DEVELOPMENT", "")
	t.Setenv("MAX_PORTS_PER_SCAN", "")
	t.Setenv("MAX_CONCURRENT_PORTS", "")
	t.Setenv("SCAN_TIMEOUT_MS", "")
	t.Setenv("ALLOWED_TARGETS", "")
	t.Setenv("MAX_ACTIVE_SCANS", "")
	t.Setenv("MAX_RETAINED_JOBS", "")

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
	if config.MaxActiveScans != defaultMaxActiveScans {
		t.Fatalf("expected max active scans %d, got %d", defaultMaxActiveScans, config.MaxActiveScans)
	}
	if config.MaxRetainedJobs != defaultMaxRetainedJobs {
		t.Fatalf("expected max retained jobs %d, got %d", defaultMaxRetainedJobs, config.MaxRetainedJobs)
	}
}

func TestLoadRejectsInvalidValues(t *testing.T) {
	tests := []struct {
		name  string
		key   string
		value string
	}{
		{
			name:  "invalid isolated development boolean",
			key:   "SCANNER_ISOLATED_DEVELOPMENT",
			value: "maybe",
		},
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
			name:  "max ports above hard limit",
			key:   "MAX_PORTS_PER_SCAN",
			value: "1001",
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
		{
			name:  "invalid active scan limit",
			key:   "MAX_ACTIVE_SCANS",
			value: "0",
		},
		{
			name:  "invalid retained job limit",
			key:   "MAX_RETAINED_JOBS",
			value: "-1",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			t.Setenv("ALLOW_PRIVATE_TARGETS", "")
			t.Setenv("SCANNER_ISOLATED_DEVELOPMENT", "")
			t.Setenv("MAX_PORTS_PER_SCAN", "")
			t.Setenv("MAX_CONCURRENT_PORTS", "")
			t.Setenv("SCAN_TIMEOUT_MS", "")
			t.Setenv("ALLOWED_TARGETS", "")
			t.Setenv("MAX_ACTIVE_SCANS", "")
			t.Setenv("MAX_RETAINED_JOBS", "")
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
	t.Setenv("SCANNER_ISOLATED_DEVELOPMENT", "")
	t.Setenv("MAX_PORTS_PER_SCAN", "")
	t.Setenv("MAX_CONCURRENT_PORTS", "")
	t.Setenv("SCAN_TIMEOUT_MS", "")
	t.Setenv("ALLOWED_TARGETS", " Scanme.Example, 8.8.8.8 ")
	t.Setenv("MAX_ACTIVE_SCANS", "")
	t.Setenv("MAX_RETAINED_JOBS", "")

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

func TestLoadRestrictsPrivateTargetsToIsolatedDevelopment(t *testing.T) {
	t.Setenv("ALLOW_PRIVATE_TARGETS", "true")
	t.Setenv("SCANNER_ISOLATED_DEVELOPMENT", "false")
	if _, err := Load(); err == nil {
		t.Fatal("expected private targets outside isolated development to fail")
	}

	t.Setenv("SCANNER_ISOLATED_DEVELOPMENT", "true")
	config, err := Load()
	if err != nil {
		t.Fatalf("expected isolated private-target configuration to load: %v", err)
	}
	if !config.AllowPrivateTargets || !config.IsolatedDevelopment {
		t.Fatal("expected isolated development flags to be enabled")
	}
}
