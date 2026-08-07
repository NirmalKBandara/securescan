package main

import (
	"fmt"
	"sync"
	"testing"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

func TestJobStoreCreatesAndGetsJob(t *testing.T) {
	store := newJobStore(100, 1000)
	job := newScanJob("scan-1", models.ScanConfig{
		Target:    "8.8.8.8",
		StartPort: 1,
		EndPort:   100,
	})

	if err := store.create(job); err != nil {
		t.Fatalf("create job: %v", err)
	}

	storedJob, found := store.get(job.ID)
	if !found {
		t.Fatal("expected stored job to be found")
	}

	if storedJob.Status != jobStatusAccepted {
		t.Errorf(
			"expected status %q, got %q",
			jobStatusAccepted,
			storedJob.Status,
		)
	}
}

func TestJobStoreSupportsConcurrentAccess(t *testing.T) {
	store := newJobStore(100, 1000)
	const jobCount = 100

	var waitGroup sync.WaitGroup
	for index := 0; index < jobCount; index++ {
		waitGroup.Add(1)

		go func(id int) {
			defer waitGroup.Done()

			jobID := fmt.Sprintf("scan-%d", id)
			if err := store.create(newScanJob(jobID, models.ScanConfig{
				Target:    "8.8.8.8",
				StartPort: 1,
				EndPort:   10,
			})); err != nil {
				t.Errorf("create job %q: %v", jobID, err)
				return
			}

			if _, found := store.get(jobID); !found {
				t.Errorf("expected job %q to be found", jobID)
			}
		}(index)
	}

	waitGroup.Wait()
}
