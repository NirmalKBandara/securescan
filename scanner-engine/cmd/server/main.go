package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	appconfig "github.com/NirmalKBandara/securescan/scanner-engine/internal/config"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/models"
	"github.com/NirmalKBandara/securescan/scanner-engine/internal/scanner"
)

const (
	serviceAddress = ":8081"
	serviceName    = "securescan-scanner"
)

type healthResponse struct {
	Status  string `json:"status"`
	Service string `json:"service"`
}

type errorResponse struct {
	Code  string `json:"code"`
	Error string `json:"error"`
}

const (
	errorCodeBlockedTarget         = "BLOCKED_TARGET"
	errorCodeInternal              = "INTERNAL_ERROR"
	errorCodeInvalidPort           = "INVALID_PORT_RANGE"
	errorCodeInvalidRequest        = "INVALID_REQUEST"
	errorCodeInvalidScanID         = "INVALID_SCAN_ID"
	errorCodeInvalidTarget         = "INVALID_TARGET"
	errorCodeMethodNotAllowed      = "METHOD_NOT_ALLOWED"
	errorCodeScanNotFound          = "SCAN_NOT_FOUND"
	errorCodeUnsupportedType       = "UNSUPPORTED_MEDIA_TYPE"
	errorCodeInvalidIdempotencyKey = "INVALID_IDEMPOTENCY_KEY"
	errorCodeIdempotencyConflict   = "IDEMPOTENCY_CONFLICT"
	errorCodeJobLimitReached       = "JOB_LIMIT_REACHED"
)

func main() {
	if err := run(); err != nil {
		log.Printf("server failed: %v", err)
		os.Exit(1)
	}
}

func run() error {
	config, err := appconfig.Load()
	if err != nil {
		return errors.New("invalid configuration: " + err.Error())
	}

	listenAddress := serviceAddress
	if config.IsolatedDevelopment {
		// Development mode permits unpinned/private targets, so make the
		// topology locally isolated rather than trusting a flag alone.
		listenAddress = "127.0.0.1:8081"
	}
	server := &http.Server{
		Addr:    listenAddress,
		Handler: loggingMiddleware(routes(config)),
	}

	log.Printf("%s listening on %s", serviceName, listenAddress)
	serverError := make(chan error, 1)
	go func() {
		serverError <- server.ListenAndServe()
	}()

	signalContext, stop := signal.NotifyContext(
		context.Background(), os.Interrupt, syscall.SIGTERM,
	)
	defer stop()

	select {
	case err := <-serverError:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	case <-signalContext.Done():
		shutdownContext, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		log.Printf("%s shutting down", serviceName)
		if err := server.Shutdown(shutdownContext); err != nil {
			return errors.New("graceful shutdown: " + err.Error())
		}
		if err := <-serverError; err != nil && !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	}
}

func routes(config appconfig.Config) http.Handler {
	return routesWithRunner(config, scanner.Scan)
}

func routesWithRunner(
	config appconfig.Config,
	runner func(models.ScanConfig) (models.ScanResult, error),
) http.Handler {
	api := newAPI(config, runner)
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/internal/scans", api.createScanHandler)
	mux.HandleFunc("/internal/scans/", api.getScanHandler)
	return mux
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, errorResponse{
			Code:  errorCodeMethodNotAllowed,
			Error: "method not allowed",
		})
		return
	}

	writeJSON(w, http.StatusOK, healthResponse{
		Status:  "ok",
		Service: serviceName,
	})
}

func writeJSON(w http.ResponseWriter, statusCode int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("failed to encode JSON response: %v", err)
	}
}

func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestID := r.Header.Get("X-Request-ID")
		if requestID == "" {
			log.Printf("%s %s", r.Method, r.URL.Path)
		} else {
			log.Printf(
				"%s %s request_id=%s",
				r.Method,
				r.URL.Path,
				requestID,
			)
		}
		next.ServeHTTP(w, r)
	})
}
