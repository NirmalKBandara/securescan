package models

import "time"

// Contains the user-configurable scan settings.
type ScanConfig struct {
	Target              string
	StartPort           int
	EndPort             int
	Timeout             time.Duration
	AllowPrivateTargets bool
	MaxPortsPerScan     int
	MaxConcurrentPorts  int
	AllowedTargets      []string
}

// Represents the result of scanning one TCP port.
type PortResult struct {
	Port  int
	State string
	Error string
}

// Contains the complete result of one scan request.
type ScanResult struct {
	Target    string
	StartPort int
	EndPort   int
	Results   []PortResult
	Duration  time.Duration
}
