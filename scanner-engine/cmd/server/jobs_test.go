package main

import (
	"fmt"
	"sync"
	"testing"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

func TestJobStoreCreatesAndGetsJob(t *testing.T) {
	store := newJobStore()
	job := newScanJob("scan-1", models.ScanConfig{
		Target:    "8.8.8.8",
		StartPort: 1,
		EndPort:   100,
	})

	store.create(job)

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
	store := newJobStore()
	const jobCount = 100

	var waitGroup sync.WaitGroup
	for index := 0; index < jobCount; index++ {
		waitGroup.Add(1)

		go func(id int) {
			defer waitGroup.Done()

			jobID := fmt.Sprintf("scan-%d", id)
			store.create(newScanJob(jobID, models.ScanConfig{
				Target:    "8.8.8.8",
				StartPort: 1,
				EndPort:   10,
			}))

			if _, found := store.get(jobID); !found {
				t.Errorf("expected job %q to be found", jobID)
			}
		}(index)
	}

	waitGroup.Wait()
}
