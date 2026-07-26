package main

import (
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

func TestGetScanReturnsStoredJob(t *testing.T) {
	api := newAPI(testConfig(), successfulTestScan)
	job := newScanJob("scan-123", models.ScanConfig{
		Target:    "8.8.8.8",
		StartPort: 1,
		EndPort:   10,
	})
	api.jobs.create(job)

	request := httptest.NewRequest(
		http.MethodGet,
		"/internal/scans/"+job.ID,
		nil,
	)
	recorder := httptest.NewRecorder()

	api.getScanHandler(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	var response scanJob
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode scan job: %v", err)
	}

	if response.ID != job.ID {
		t.Errorf("expected job ID %q, got %q", job.ID, response.ID)
	}
}

func TestGetScanReturnsNotFound(t *testing.T) {
	api := newAPI(testConfig(), successfulTestScan)
	request := httptest.NewRequest(
		http.MethodGet,
		"/internal/scans/unknown",
		nil,
	)
	recorder := httptest.NewRecorder()

	api.getScanHandler(recorder, request)

	if recorder.Code != http.StatusNotFound {
		t.Fatalf(
			"expected status %d, got %d",
			http.StatusNotFound,
			recorder.Code,
		)
	}
}

func TestRunScanCompletesJob(t *testing.T) {
	api := newAPI(testConfig(), successfulTestScan)
	config := models.ScanConfig{
		Target:    "8.8.8.8",
		StartPort: 1,
		EndPort:   2,
	}
	job := newScanJob("scan-complete", config)
	api.jobs.create(job)

	api.runScan(job.ID, config)

	completedJob, _ := api.jobs.get(job.ID)
	if completedJob.Status != jobStatusCompleted {
		t.Errorf("expected completed status, got %q", completedJob.Status)
	}

	if completedJob.Result == nil {
		t.Fatal("expected completed scan result")
	}
}

func TestRunScanMarksFailedJob(t *testing.T) {
	api := newAPI(
		testConfig(),
		func(models.ScanConfig) (models.ScanResult, error) {
			return models.ScanResult{}, errors.New("scan failed")
		},
	)
	job := newScanJob("scan-failed", models.ScanConfig{})
	api.jobs.create(job)

	api.runScan(job.ID, models.ScanConfig{})

	failedJob, _ := api.jobs.get(job.ID)
	if failedJob.Status != jobStatusFailed {
		t.Errorf("expected failed status, got %q", failedJob.Status)
	}

	if failedJob.Error != "scan failed" {
		t.Errorf("expected scan failure message, got %q", failedJob.Error)
	}
}

func successfulTestScan(
	config models.ScanConfig,
) (models.ScanResult, error) {
	return models.ScanResult{
		Target:    config.Target,
		StartPort: config.StartPort,
		EndPort:   config.EndPort,
		Results: []models.PortResult{
			{Port: config.StartPort, State: "closed"},
		},
	}, nil
}
