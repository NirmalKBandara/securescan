package main

import (
	"flag"
	"fmt"
	"log"
	"os"

	appconfig "github.com/NirmalKBandara/securescan/scanner-engine/internal/config"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/scanner"
)

func main() {
	target := flag.String(
		"target",
		"",
		"authorized hostname or IP address to scan",
	)

	startPort := flag.Int(
		"start-port",
		1,
		"first TCP port to scan",
	)

	endPort := flag.Int(
		"end-port",
		100,
		"last TCP port to scan",
	)

	flag.Parse()

	appConfig, err := appconfig.Load()
	if err != nil {
		log.Printf("invalid configuration: %v", err)
		os.Exit(1)
	}

	scanConfig := models.ScanConfig{
		Target:              *target,
		StartPort:           *startPort,
		EndPort:             *endPort,
		Timeout:             appConfig.ScanTimeout,
		AllowPrivateTargets: appConfig.AllowPrivateTargets,
		MaxPortsPerScan:     appConfig.MaxPortsPerScan,
		MaxConcurrentPorts:  appConfig.MaxConcurrentPorts,
		AllowedTargets:      appConfig.AllowedTargets,
	}

	result, err := scanner.Scan(scanConfig)
	if err != nil {
		log.Printf("scan failed: %v", err)
		os.Exit(1)
	}

	printResult(result)
}

func printResult(result models.ScanResult) {
	fmt.Println("SecureScan TCP Connect Scanner")
	fmt.Println("------------------------------")
	fmt.Printf("Target: %s\n", result.Target)
	fmt.Printf(
		"Port range: %d-%d\n",
		result.StartPort,
		result.EndPort,
	)
	fmt.Printf("Duration: %s\n\n", result.Duration)

	openPortCount := 0

	for _, portResult := range result.Results {
		if portResult.State == "open" {
			fmt.Printf("[OPEN] Port %d\n", portResult.Port)
			openPortCount++
		}
	}

	fmt.Printf("\nOpen ports found: %d\n", openPortCount)
	fmt.Printf("Ports checked: %d\n", len(result.Results))
}
