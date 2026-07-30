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
	Address string `json:"address,omitempty"`
	Port    int    `json:"port"`
	State   string `json:"state"`
	Error   string `json:"error,omitempty"`
}

// Contains the complete result of one scan request.
type ScanResult struct {
	Target    string        `json:"target"`
	StartPort int           `json:"startPort"`
	EndPort   int           `json:"endPort"`
	Results   []PortResult  `json:"results"`
	Duration  time.Duration `json:"duration"`
}
