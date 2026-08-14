package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	defaultMaxPorts        = 1000
	defaultMaxConcurrency  = 100
	defaultScanTimeoutMS   = 1000
	defaultMaxActiveScans  = 10
	defaultMaxRetainedJobs = 1000
)

type Config struct {
	AllowPrivateTargets bool
	MaxPortsPerScan     int
	MaxConcurrentPorts  int
	ScanTimeout         time.Duration
	AllowedTargets      []string
	MaxActiveScans      int
	MaxRetainedJobs     int
}

func Load() (Config, error) {
	allowPrivate, err := readBool("ALLOW_PRIVATE_TARGETS", false)
	if err != nil {
		return Config{}, err
	}
	maxPorts, err := readPositiveInt(
		"MAX_PORTS_PER_SCAN",
		defaultMaxPorts,
	)
	if err != nil {
		return Config{}, err
	}
	if maxPorts > defaultMaxPorts {
		return Config{}, fmt.Errorf(
			"MAX_PORTS_PER_SCAN cannot exceed hard limit %d",
			defaultMaxPorts,
		)
	}

	maxConcurrency, err := readPositiveInt(
		"MAX_CONCURRENT_PORTS",
		defaultMaxConcurrency,
	)
	if err != nil {
		return Config{}, err
	}

	timeoutMS, err := readPositiveInt(
		"SCAN_TIMEOUT_MS",
		defaultScanTimeoutMS,
	)
	if err != nil {
		return Config{}, err
	}

	maxActiveScans, err := readPositiveInt(
		"MAX_ACTIVE_SCANS",
		defaultMaxActiveScans,
	)
	if err != nil {
		return Config{}, err
	}

	maxRetainedJobs, err := readPositiveInt(
		"MAX_RETAINED_JOBS",
		defaultMaxRetainedJobs,
	)
	if err != nil {
		return Config{}, err
	}

	return Config{
		AllowPrivateTargets: allowPrivate,
		MaxPortsPerScan:     maxPorts,
		MaxConcurrentPorts:  maxConcurrency,
		ScanTimeout:         time.Duration(timeoutMS) * time.Millisecond,
		AllowedTargets:      readCSV("ALLOWED_TARGETS"),
		MaxActiveScans:      maxActiveScans,
		MaxRetainedJobs:     maxRetainedJobs,
	}, nil
}

func readBool(name string, fallback bool) (bool, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, nil
	}

	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf(
			"%s must be true or false: %w",
			name,
			err,
		)
	}
	return parsed, nil
}

func readPositiveInt(name string, fallback int) (int, error) {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback, nil
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return 0, fmt.Errorf("%s must be an integer: %w", name, err)
	}

	if parsed <= 0 {
		return 0, fmt.Errorf("%s must be greater than zero", name)
	}
	return parsed, nil
}

func readCSV(name string) []string {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return nil
	}
	parts := strings.Split(value, ",")
	result := make([]string, 0, len(parts))

	for _, part := range parts {
		item := strings.ToLower(strings.TrimSpace(part))
		if item != "" {
			result = append(result, item)
		}
	}
	return result
}
