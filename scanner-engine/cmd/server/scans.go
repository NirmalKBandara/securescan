package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	appconfig "github.com/NirmalKBandara/securescan/scanner-engine/internal/config"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/validation"
)

const maximumRequestBodyBytes = 4096

type api struct {
	config appconfig.Config
	jobs   *jobStore
	scan   scanRunner
}

type createScanRequest struct {
	Target    string `json:"target"`
	StartPort int    `json:"startPort"`
	EndPort   int    `json:"endPort"`
}

type createScanResponse struct {
	ID        string `json:"id"`
	Status    string `json:"status"`
	Target    string `json:"target"`
	StartPort int    `json:"startPort"`
	EndPort   int    `json:"endPort"`
}

type scanRunner func(models.ScanConfig) (models.ScanResult, error)

func newAPI(config appconfig.Config, runner scanRunner) *api {
	return &api{
		config: config,
		jobs:   newJobStore(),
		scan:   runner,
	}
}

func (api *api) createScanHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, errorResponse{
			Code:  errorCodeMethodNotAllowed,
			Error: "method not allowed",
		})
		return
	}

	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		writeJSON(w, http.StatusUnsupportedMediaType, errorResponse{
			Code:  errorCodeUnsupportedType,
			Error: "Content-Type must be application/json",
		})
		return
	}

	var request createScanRequest
	if err := decodeJSONBody(w, r, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Code:  errorCodeInvalidRequest,
			Error: err.Error(),
		})
		return
	}

	// API input is converted into the same configuration used by the CLI.
	scanConfig := models.ScanConfig{
		Target:              request.Target,
		StartPort:           request.StartPort,
		EndPort:             request.EndPort,
		Timeout:             api.config.ScanTimeout,
		AllowPrivateTargets: api.config.AllowPrivateTargets,
		MaxPortsPerScan:     api.config.MaxPortsPerScan,
		MaxConcurrentPorts:  api.config.MaxConcurrentPorts,
		AllowedTargets:      api.config.AllowedTargets,
	}

	if err := validation.ValidateScanConfig(scanConfig); err != nil {
		code := errorCodeInvalidPort
		if strings.TrimSpace(scanConfig.Target) == "" {
			code = errorCodeInvalidTarget
		}
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Code:  code,
			Error: err.Error(),
		})
		return
	}

	// Prevents an unsafe target from becoming an accepted job.
	if _, err := validation.ValidateTarget(
		scanConfig.Target,
		scanConfig.AllowPrivateTargets,
		scanConfig.AllowedTargets,
	); err != nil {
		code := errorCodeInvalidTarget
		if validation.IsBlockedTargetError(err) {
			code = errorCodeBlockedTarget
		}
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Code:  code,
			Error: err.Error(),
		})
		return
	}

	id, err := newUUID()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, errorResponse{
			Code:  errorCodeInternal,
			Error: "failed to create scan ID",
		})
		return
	}

	job := newScanJob(id, scanConfig)
	api.jobs.create(job)

	writeJSON(w, http.StatusAccepted, createScanResponse{
		ID:        job.ID,
		Status:    job.Status,
		Target:    job.Target,
		StartPort: job.StartPort,
		EndPort:   job.EndPort,
	})

	// The HTTP request can finish while the scan continues in the background.
	go api.runScan(job.ID, scanConfig)
}

func (api *api) runScan(id string, config models.ScanConfig) {
	api.jobs.markRunning(id)

	result, err := api.scan(config)
	if err != nil {
		api.jobs.markFailed(id, err)
		return
	}

	api.jobs.markCompleted(id, result)
}

func decodeJSONBody(
	w http.ResponseWriter,
	r *http.Request,
	destination any,
) error {

	// Protects the internal service from oversized JSON requests.
	r.Body = http.MaxBytesReader(w, r.Body, maximumRequestBodyBytes)

	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()

	if err := decoder.Decode(destination); err != nil {
		return errors.New("request body must contain valid scan JSON")
	}

	// Only one JSON value is allowed | trailing data may indicate a malformed
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("request body must contain one JSON object")
	}

	return nil
}
