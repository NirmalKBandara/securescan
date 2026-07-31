package main

import (
	"net/http"
	"strings"
)

func (api *api) getScanHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, errorResponse{
			Code:  errorCodeMethodNotAllowed,
			Error: "method not allowed",
		})
		return
	}

	id := strings.TrimPrefix(r.URL.Path, "/internal/scans/")
	if id == "" || strings.Contains(id, "/") {
		writeJSON(w, http.StatusBadRequest, errorResponse{
			Code:  errorCodeInvalidScanID,
			Error: "scan ID is required",
		})
		return
	}

	job, found := api.jobs.get(id)
	if !found {
		writeJSON(w, http.StatusNotFound, errorResponse{
			Code:  errorCodeScanNotFound,
			Error: "scan job not found",
		})
		return
	}

	writeJSON(w, http.StatusOK, job)
}
