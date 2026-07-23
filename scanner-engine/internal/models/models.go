package models

import "time"

// ScanConfig contains the user-configurable scan settings.
type ScanConfig struct {
	Target    string
	StartPort int
	EndPort   int
	Timeout   time.Duration
}

// PortResult represents the result of scanning one TCP port.
type PortResult struct {
	Port  int
	State string
	Error string
}

// ScanResult contains the complete result of one scan request.
type ScanResult struct {
	Target    string
	StartPort int
	EndPort   int
	Results   []PortResult
	Duration  time.Duration
}