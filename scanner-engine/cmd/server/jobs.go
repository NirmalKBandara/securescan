package main

import (
	"sync"
	"time"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

const (
	jobStatusAccepted  = "accepted"
	jobStatusRunning   = "running"
	jobStatusCompleted = "completed"
	jobStatusFailed    = "failed"
)

type scanJob struct {
	ID        string             `json:"id"`
	Status    string             `json:"status"`
	Target    string             `json:"target"`
	StartPort int                `json:"startPort"`
	EndPort   int                `json:"endPort"`
	CreatedAt time.Time          `json:"createdAt"`
	UpdatedAt time.Time          `json:"updatedAt"`
	Result    *models.ScanResult `json:"result,omitempty"`
	Error     string             `json:"error,omitempty"`
}

type jobStore struct {
	// HTTP handlers run concurrently.
	mu   sync.RWMutex
	jobs map[string]scanJob
}

func newJobStore() *jobStore {
	return &jobStore{
		jobs: make(map[string]scanJob),
	}
}

func newScanJob(id string, config models.ScanConfig) scanJob {
	now := time.Now().UTC()

	return scanJob{
		ID:        id,
		Status:    jobStatusAccepted,
		Target:    config.Target,
		StartPort: config.StartPort,
		EndPort:   config.EndPort,
		CreatedAt: now,
		UpdatedAt: now,
	}
}

func (store *jobStore) create(job scanJob) {
	store.mu.Lock()
	defer store.mu.Unlock()

	store.jobs[job.ID] = job
}

func (store *jobStore) get(id string) (scanJob, bool) {
	store.mu.RLock()
	defer store.mu.RUnlock()

	job, found := store.jobs[id]
	return job, found
}

func (store *jobStore) markRunning(id string) {
	store.update(id, func(job *scanJob) {
		job.Status = jobStatusRunning
	})
}

func (store *jobStore) markCompleted(id string, result models.ScanResult) {
	store.update(id, func(job *scanJob) {
		job.Status = jobStatusCompleted
		job.Result = &result
		job.Error = ""
	})
}

func (store *jobStore) markFailed(id string, err error) {
	store.update(id, func(job *scanJob) {
		job.Status = jobStatusFailed
		job.Error = err.Error()
		job.Result = nil
	})
}

func (store *jobStore) update(id string, change func(*scanJob)) {
	store.mu.Lock()
	defer store.mu.Unlock()

	job, found := store.jobs[id]
	if !found {
		return
	}

	change(&job)
	job.UpdatedAt = time.Now().UTC()
	store.jobs[id] = job
}
