package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	appconfig "github.com/NirmalKBandara/securescan/scanner-engine/internal/config"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

func TestCreateScanAcceptsValidRequest(t *testing.T) {
	body := bytes.NewBufferString(
		`{"target":"8.8.8.8","startPort":1,"endPort":100}`,
	)
	request := httptest.NewRequest(http.MethodPost, "/internal/scans", body)
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()

	testRoutes().ServeHTTP(recorder, request)
	if recorder.Code != http.StatusAccepted {
		t.Fatalf(
			"expected status %d, got %d: %s",
			http.StatusAccepted,
			recorder.Code,
			recorder.Body.String(),
		)
	}

	var response createScanResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode create scan response: %v", err)
	}

	uuidPattern := regexp.MustCompile(
		`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`,
	)

	if !uuidPattern.MatchString(response.ID) {
		t.Errorf("expected UUID v4 scan ID, got %q", response.ID)
	}

	if response.Status != "accepted" {
		t.Errorf("expected accepted status, got %q", response.Status)
	}
}

func TestCreateScanRejectsInvalidRequests(t *testing.T) {
	tests := []struct {
		name         string
		body         string
		contentType  string
		expectedCode int
		errorCode    string
		expectedText string
	}{
		{
			name:         "malformed JSON",
			body:         `{"target":`,
			contentType:  "application/json",
			expectedCode: http.StatusBadRequest,
			errorCode:    errorCodeInvalidRequest,
			expectedText: "valid scan JSON",
		},
		{
			name:         "unknown JSON field",
			body:         `{"target":"8.8.8.8","startPort":1,"endPort":2,"extra":true}`,
			contentType:  "application/json",
			expectedCode: http.StatusBadRequest,
			errorCode:    errorCodeInvalidRequest,
			expectedText: "valid scan JSON",
		},
		{
			name:         "reversed port range",
			body:         `{"target":"8.8.8.8","startPort":100,"endPort":1}`,
			contentType:  "application/json",
			expectedCode: http.StatusBadRequest,
			errorCode:    errorCodeInvalidPort,
			expectedText: "start port cannot be greater",
		},
		{
			name:         "blocked loopback target",
			body:         `{"target":"127.0.0.1","startPort":1,"endPort":2}`,
			contentType:  "application/json",
			expectedCode: http.StatusBadRequest,
			errorCode:    errorCodeBlockedTarget,
			expectedText: "blocked",
		},
		{
			name:         "wrong content type",
			body:         `{"target":"8.8.8.8","startPort":1,"endPort":2}`,
			contentType:  "text/plain",
			expectedCode: http.StatusUnsupportedMediaType,
			errorCode:    errorCodeUnsupportedType,
			expectedText: "application/json",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(
				http.MethodPost,
				"/internal/scans",
				strings.NewReader(test.body),
			)
			request.Header.Set("Content-Type", test.contentType)
			recorder := httptest.NewRecorder()

			testRoutes().ServeHTTP(recorder, request)

			if recorder.Code != test.expectedCode {
				t.Fatalf(
					"expected status %d, got %d",
					test.expectedCode,
					recorder.Code,
				)
			}

			if !strings.Contains(recorder.Body.String(), test.expectedText) {
				t.Errorf(
					"expected response to contain %q, got %q",
					test.expectedText,
					recorder.Body.String(),
				)
			}

			var response errorResponse
			if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
				t.Fatalf("decode error response: %v", err)
			}
			if response.Code != test.errorCode {
				t.Errorf(
					"expected error code %q, got %q",
					test.errorCode,
					response.Code,
				)
			}
		})
	}
}

func testConfig() appconfig.Config {
	return appconfig.Config{
		MaxPortsPerScan:    1000,
		MaxConcurrentPorts: 100,
		ScanTimeout:        time.Second,
	}
}

func testRoutes() http.Handler {
	return routesWithRunner(
		testConfig(),
		func(config models.ScanConfig) (models.ScanResult, error) {
			return models.ScanResult{
				Target:    config.Target,
				StartPort: config.StartPort,
				EndPort:   config.EndPort,
				Results:   []models.PortResult{},
			}, nil
		},
	)
}
