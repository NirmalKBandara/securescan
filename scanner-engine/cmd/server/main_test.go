package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	appconfig "github.com/NirmalKBandara/securescan/scanner-engine/internal/config"
)

func TestHealthEndpoint(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	recorder := httptest.NewRecorder()
	routes(appconfig.Config{}).ServeHTTP(recorder, request)
	if recorder.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, recorder.Code)
	}

	if contentType := recorder.Header().Get("Content-Type"); contentType != "application/json" {
		t.Fatalf("expected application/json content type, got %q", contentType)
	}

	var response healthResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode health response: %v", err)
	}

	if response.Status != "ok" {
		t.Errorf("expected status ok, got %q", response.Status)
	}

	if response.Service != serviceName {
		t.Errorf("expected service %q, got %q", serviceName, response.Service)
	}
}

func TestHealthEndpointRejectsNonGETMethods(t *testing.T) {
	request := httptest.NewRequest(http.MethodPost, "/health", nil)
	recorder := httptest.NewRecorder()
	routes(appconfig.Config{}).ServeHTTP(recorder, request)
	if recorder.Code != http.StatusMethodNotAllowed {
		t.Fatalf(
			"expected status %d, got %d",
			http.StatusMethodNotAllowed,
			recorder.Code,
		)
	}
}
