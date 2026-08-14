package main

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
)

var (
	errActiveJobLimit      = errors.New("active scan job limit reached")
	errIdempotencyConflict = errors.New("idempotency key was already used for another scan request")
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
	mu              sync.RWMutex
	jobs            map[string]scanJob
	idempotencyKeys map[string]string
	maxActive       int
	maxRetained     int
}

func newJobStore(maxActive, maxRetained int) *jobStore {
	return &jobStore{
		jobs:            make(map[string]scanJob),
		idempotencyKeys: make(map[string]string),
		maxActive:       maxActive,
		maxRetained:     maxRetained,
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

func (store *jobStore) create(job scanJob) error {
	_, _, err := store.admit(job, "")
	return err
}

// admit atomically applies idempotency and the global active-job limit. The
// boolean result is true only when the caller must start a new scan goroutine.
func (store *jobStore) admit(job scanJob, idempotencyKey string) (scanJob, bool, error) {
	store.mu.Lock()
	defer store.mu.Unlock()

	if idempotencyKey != "" {
		if existingID, found := store.idempotencyKeys[idempotencyKey]; found {
			existing, retained := store.jobs[existingID]
			if retained {
				if !sameScanRequest(existing, job) {
					return scanJob{}, false, errIdempotencyConflict
				}
				return existing, false, nil
			}
			delete(store.idempotencyKeys, idempotencyKey)
		}
	}

	if store.activeCountLocked() >= store.maxActive {
		return scanJob{}, false, errActiveJobLimit
	}

	store.jobs[job.ID] = job
	if idempotencyKey != "" {
		store.idempotencyKeys[idempotencyKey] = job.ID
	}
	return job, true, nil
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
	store.enforceRetentionLocked()
}

func sameScanRequest(left, right scanJob) bool {
	return left.Target == right.Target && left.StartPort == right.StartPort && left.EndPort == right.EndPort
}

func (store *jobStore) activeCountLocked() int {
	count := 0
	for _, job := range store.jobs {
		if job.Status == jobStatusAccepted || job.Status == jobStatusRunning {
			count++
		}
	}
	return count
}

func (store *jobStore) enforceRetentionLocked() {
	type terminalJob struct {
		id        string
		updatedAt time.Time
	}
	terminal := make([]terminalJob, 0)
	for id, job := range store.jobs {
		if job.Status == jobStatusCompleted || job.Status == jobStatusFailed {
			terminal = append(terminal, terminalJob{id: id, updatedAt: job.UpdatedAt})
		}
	}
	if len(terminal) <= store.maxRetained {
		return
	}
	sort.Slice(terminal, func(i, j int) bool {
		if terminal[i].updatedAt.Equal(terminal[j].updatedAt) {
			return terminal[i].id < terminal[j].id
		}
		return terminal[i].updatedAt.Before(terminal[j].updatedAt)
	})
	for _, expired := range terminal[:len(terminal)-store.maxRetained] {
		delete(store.jobs, expired.id)
		for key, id := range store.idempotencyKeys {
			if id == expired.id {
				delete(store.idempotencyKeys, key)
			}
		}
	}
}
