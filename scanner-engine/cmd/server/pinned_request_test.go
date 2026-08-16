package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

func TestCreateScanRequiresAuthorizedAddressesOutsideIsolatedDevelopment(t *testing.T) {
	config := testConfig()
	config.IsolatedDevelopment = false
	request := httptest.NewRequest(http.MethodPost, "/internal/scans", strings.NewReader(
		`{"target":"8.8.8.8","startPort":53,"endPort":53}`,
	))
	request.Header.Set("Content-Type", "application/json")
	recorder := httptest.NewRecorder()
	routesWithRunner(config, func(scanConfig models.ScanConfig) (models.ScanResult, error) {
		t.Fatal("unauthorized request must not start a scanner job")
		return models.ScanResult{}, nil
	}).ServeHTTP(recorder, request)

	if recorder.Code != http.StatusBadRequest || !strings.Contains(recorder.Body.String(), "authorized address set is required") {
		t.Fatalf("expected missing pin rejection, got %d: %s", recorder.Code, recorder.Body.String())
	}
}
