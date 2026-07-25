package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestCreateThenGetCompletedScan(t *testing.T) {
	handler := testRoutes()

	createRequest := httptest.NewRequest(
		http.MethodPost,
		"/internal/scans",
		strings.NewReader(
			`{"target":"8.8.8.8","startPort":53,"endPort":53}`,
		),
	)
	createRequest.Header.Set("Content-Type", "application/json")
	createRecorder := httptest.NewRecorder()
	handler.ServeHTTP(createRecorder, createRequest)

	var created createScanResponse
	if err := json.NewDecoder(createRecorder.Body).Decode(&created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	deadline := time.Now().Add(time.Second)
	for {
		job := getTestJob(t, handler, created.ID)
		if job.Status == jobStatusCompleted {
			if job.Result == nil {
				t.Fatal("expected completed job to contain a result")
			}
			return
		}

		if time.Now().After(deadline) {
			t.Fatalf("job did not complete; last status was %q", job.Status)
		}

		time.Sleep(time.Millisecond)
	}
}

func TestServiceHandlesConcurrentScanRequests(t *testing.T) {
	handler := testRoutes()

	const requestCount = 20
	var waitGroup sync.WaitGroup

	for index := 0; index < requestCount; index++ {
		waitGroup.Add(1)

		go func() {
			defer waitGroup.Done()

			request := httptest.NewRequest(
				http.MethodPost,
				"/internal/scans",
				strings.NewReader(
					`{"target":"8.8.8.8","startPort":1,"endPort":2}`,
				),
			)
			request.Header.Set("Content-Type", "application/json")
			recorder := httptest.NewRecorder()
			handler.ServeHTTP(recorder, request)

			if recorder.Code != http.StatusAccepted {
				t.Errorf(
					"expected status %d, got %d",
					http.StatusAccepted,
					recorder.Code,
				)
			}
		}()
	}

	waitGroup.Wait()
}

func getTestJob(t *testing.T, handler http.Handler, id string) scanJob {
	t.Helper()

	request := httptest.NewRequest(
		http.MethodGet,
		"/internal/scans/"+id,
		nil,
	)
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, request)

	if recorder.Code != http.StatusOK {
		t.Fatalf(
			"expected status %d, got %d",
			http.StatusOK,
			recorder.Code,
		)
	}

	var job scanJob
	if err := json.NewDecoder(recorder.Body).Decode(&job); err != nil {
		t.Fatalf("decode scan job: %v", err)
	}

	return job
}
