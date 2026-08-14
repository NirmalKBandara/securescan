package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

const (
	testIdempotencyKeyOne = "10000000-0000-4000-8000-000000000001"
	testIdempotencyKeyTwo = "10000000-0000-4000-8000-000000000002"
)

func TestCreateScanReusesIdempotentJob(t *testing.T) {
	var runs atomic.Int32
	api := newAPI(testConfig(), func(config models.ScanConfig) (models.ScanResult, error) {
		runs.Add(1)
		return successfulTestScan(config)
	})

	first := createTestScan(t, api, testIdempotencyKeyOne, 53, 53)
	second := createTestScan(t, api, testIdempotencyKeyOne, 53, 53)

	if first.Code != http.StatusAccepted || second.Code != http.StatusAccepted {
		t.Fatalf("expected both requests accepted, got %d and %d", first.Code, second.Code)
	}
	firstResponse := decodeCreateResponse(t, first)
	secondResponse := decodeCreateResponse(t, second)
	if firstResponse.ID != secondResponse.ID {
		t.Fatalf("expected retry to reuse job %q, got %q", firstResponse.ID, secondResponse.ID)
	}

	waitForRunCount(t, &runs, 1)
	waitForJobStatus(t, api.jobs, firstResponse.ID, jobStatusCompleted)
	terminalRetry := createTestScan(t, api, testIdempotencyKeyOne, 53, 53)
	if terminalRetry.Code != http.StatusAccepted || decodeCreateResponse(t, terminalRetry).ID != firstResponse.ID {
		t.Fatal("expected retry of retained terminal job to reuse the original job")
	}
	time.Sleep(10 * time.Millisecond)
	if runs.Load() != 1 {
		t.Fatalf("expected one scan execution, got %d", runs.Load())
	}
}

func TestCreateScanRejectsConflictingIdempotencyKey(t *testing.T) {
	release := make(chan struct{})
	api := newAPI(testConfig(), func(config models.ScanConfig) (models.ScanResult, error) {
		<-release
		return successfulTestScan(config)
	})

	first := createTestScan(t, api, testIdempotencyKeyOne, 53, 53)
	if first.Code != http.StatusAccepted {
		close(release)
		t.Fatalf("expected first request accepted, got %d", first.Code)
	}
	conflict := createTestScan(t, api, testIdempotencyKeyOne, 53, 54)
	close(release)

	assertErrorResponse(t, conflict, http.StatusConflict, errorCodeIdempotencyConflict)
}

func TestCreateScanRejectsInvalidIdempotencyKey(t *testing.T) {
	api := newAPI(testConfig(), successfulTestScan)
	response := createTestScan(t, api, "not-a-uuid", 53, 53)
	assertErrorResponse(t, response, http.StatusBadRequest, errorCodeInvalidIdempotencyKey)
}

func TestCreateScanEnforcesGlobalActiveLimit(t *testing.T) {
	config := testConfig()
	config.MaxActiveScans = 1
	release := make(chan struct{})
	api := newAPI(config, func(scanConfig models.ScanConfig) (models.ScanResult, error) {
		<-release
		return successfulTestScan(scanConfig)
	})

	first := createTestScan(t, api, testIdempotencyKeyOne, 53, 53)
	if first.Code != http.StatusAccepted {
		close(release)
		t.Fatalf("expected first request accepted, got %d", first.Code)
	}
	limited := createTestScan(t, api, testIdempotencyKeyTwo, 54, 54)
	assertErrorResponse(t, limited, http.StatusTooManyRequests, errorCodeJobLimitReached)

	retry := createTestScan(t, api, testIdempotencyKeyOne, 53, 53)
	if retry.Code != http.StatusAccepted {
		close(release)
		t.Fatalf("expected idempotent retry accepted at capacity, got %d", retry.Code)
	}
	close(release)
	firstID := decodeCreateResponse(t, first).ID
	waitForJobStatus(t, api.jobs, firstID, jobStatusCompleted)
	afterCompletion := createTestScan(t, api, testIdempotencyKeyTwo, 54, 54)
	if afterCompletion.Code != http.StatusAccepted {
		t.Fatalf("expected capacity to be released after completion, got %d", afterCompletion.Code)
	}
}

func TestConcurrentIdempotentCreatesStartOneScan(t *testing.T) {
	const requestCount = 20
	var runs atomic.Int32
	release := make(chan struct{})
	api := newAPI(testConfig(), func(config models.ScanConfig) (models.ScanResult, error) {
		runs.Add(1)
		<-release
		return successfulTestScan(config)
	})

	var waitGroup sync.WaitGroup
	responses := make(chan string, requestCount)
	for index := 0; index < requestCount; index++ {
		waitGroup.Add(1)
		go func() {
			defer waitGroup.Done()
			recorder := createTestScan(t, api, testIdempotencyKeyOne, 53, 53)
			if recorder.Code != http.StatusAccepted {
				t.Errorf("expected accepted response, got %d", recorder.Code)
				return
			}
			responses <- decodeCreateResponse(t, recorder).ID
		}()
	}
	waitGroup.Wait()
	close(responses)
	close(release)

	var expectedID string
	for id := range responses {
		if expectedID == "" {
			expectedID = id
		}
		if id != expectedID {
			t.Errorf("expected one scanner job ID %q, got %q", expectedID, id)
		}
	}
	waitForRunCount(t, &runs, 1)
	if runs.Load() != 1 {
		t.Fatalf("expected one scan execution, got %d", runs.Load())
	}
}

func TestJobStoreEvictsOldestTerminalJobs(t *testing.T) {
	store := newJobStore(10, 2)
	jobs := []scanJob{
		newScanJob("scan-1", models.ScanConfig{Target: "8.8.8.8", StartPort: 1, EndPort: 1}),
		newScanJob("scan-2", models.ScanConfig{Target: "8.8.8.8", StartPort: 2, EndPort: 2}),
		newScanJob("scan-3", models.ScanConfig{Target: "8.8.8.8", StartPort: 3, EndPort: 3}),
	}

	for index, job := range jobs {
		key := []string{testIdempotencyKeyOne, testIdempotencyKeyTwo, "10000000-0000-4000-8000-000000000003"}[index]
		if _, created, err := store.admit(job, key); err != nil || !created {
			t.Fatalf("admit job %d: created=%v err=%v", index, created, err)
		}
		store.markCompleted(job.ID, models.ScanResult{})
		time.Sleep(time.Millisecond)
	}

	if _, found := store.get("scan-1"); found {
		t.Fatal("expected oldest terminal job to be evicted")
	}
	if _, found := store.get("scan-2"); !found {
		t.Fatal("expected newer terminal job to remain")
	}
	if _, found := store.get("scan-3"); !found {
		t.Fatal("expected newest terminal job to remain")
	}
	replacement := newScanJob("scan-4", models.ScanConfig{Target: "8.8.8.8", StartPort: 1, EndPort: 1})
	if admitted, created, err := store.admit(replacement, testIdempotencyKeyOne); err != nil || !created || admitted.ID != replacement.ID {
		t.Fatalf("expected evicted idempotency key to be reusable: created=%v err=%v", created, err)
	}
}

func createTestScan(t *testing.T, api *api, key string, startPort, endPort int) *httptest.ResponseRecorder {
	t.Helper()
	body := strings.NewReader(
		`{"target":"8.8.8.8","startPort":` + strconv.Itoa(startPort) +
			`,"endPort":` + strconv.Itoa(endPort) + `}`,
	)
	request := httptest.NewRequest(http.MethodPost, "/internal/scans", body)
	request.Header.Set("Content-Type", "application/json")
	if key != "" {
		request.Header.Set(idempotencyHeader, key)
	}
	recorder := httptest.NewRecorder()
	api.createScanHandler(recorder, request)
	return recorder
}

func decodeCreateResponse(t *testing.T, recorder *httptest.ResponseRecorder) createScanResponse {
	t.Helper()
	var response createScanResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode create response: %v", err)
	}
	return response
}

func assertErrorResponse(t *testing.T, recorder *httptest.ResponseRecorder, status int, code string) {
	t.Helper()
	if recorder.Code != status {
		t.Fatalf("expected status %d, got %d: %s", status, recorder.Code, recorder.Body.String())
	}
	var response errorResponse
	if err := json.NewDecoder(recorder.Body).Decode(&response); err != nil {
		t.Fatalf("decode error response: %v", err)
	}
	if response.Code != code {
		t.Fatalf("expected error code %q, got %q", code, response.Code)
	}
}

func waitForRunCount(t *testing.T, runs *atomic.Int32, expected int32) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for runs.Load() != expected {
		if time.Now().After(deadline) {
			t.Fatalf("expected %d scan runs, got %d", expected, runs.Load())
		}
		time.Sleep(time.Millisecond)
	}
}

func waitForJobStatus(t *testing.T, store *jobStore, id, expected string) {
	t.Helper()
	deadline := time.Now().Add(time.Second)
	for {
		job, found := store.get(id)
		if found && job.Status == expected {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %q did not reach %q", id, expected)
		}
		time.Sleep(time.Millisecond)
	}
}
