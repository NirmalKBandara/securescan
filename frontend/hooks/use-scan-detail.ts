"use client";

import { useCallback, useEffect, useState } from "react";
import { scansApi, SecureScanApiError } from "@/lib/api/client";
import type { ScanDetail } from "@/lib/api/types";

export const SCAN_POLL_INTERVAL_MS = 2_000;
const activeStatuses = new Set(["queued", "accepted", "running"]);

function isTemporaryFailure(error: unknown) {
  if (!(error instanceof SecureScanApiError)) return true;
  return error.status === 0 || error.status === 408 || error.status === 429 || error.status >= 500;
}

export interface ScanDetailState {
  scan: ScanDetail | null;
  loading: boolean;
  error: SecureScanApiError | null;
  retrying: boolean;
  retry: () => void;
}

export function useScanDetail(id: string): ScanDetailState {
  const [scan, setScan] = useState<ScanDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<SecureScanApiError | null>(null);
  const [retrying, setRetrying] = useState(false);
  const [requestGeneration, setRequestGeneration] = useState(0);

  useEffect(() => {
    let active = true;
    let inFlight = false;
    let timer: ReturnType<typeof setTimeout> | null = null;
    let controller: AbortController | null = null;

    const schedule = (load: () => Promise<void>) => {
      timer = setTimeout(() => void load(), SCAN_POLL_INTERVAL_MS);
    };

    const load = async () => {
      if (!active || inFlight) return;
      inFlight = true;
      controller = new AbortController();
      try {
        const nextScan = await scansApi.get(id, { signal: controller.signal });
        if (!active) return;
        setScan(nextScan);
        setError(null);
        setLoading(false);
        setRetrying(false);
        if (activeStatuses.has(nextScan.status)) schedule(load);
      } catch (caught) {
        if (!active || (caught instanceof DOMException && caught.name === "AbortError")) return;
        const temporary = isTemporaryFailure(caught);
        const nextError = caught instanceof SecureScanApiError
          ? caught
          : new SecureScanApiError("Unable to reach SecureScan. Retrying automatically.", 0);
        setError(nextError);
        setLoading(false);
        setRetrying(temporary);
        if (temporary) schedule(load);
      } finally {
        inFlight = false;
        controller = null;
      }
    };

    void load();
    return () => {
      active = false;
      if (timer !== null) clearTimeout(timer);
      controller?.abort();
    };
  }, [id, requestGeneration]);

  const retry = useCallback(() => {
    setRetrying(true);
    setRequestGeneration((generation) => generation + 1);
  }, []);

  return { scan, loading, error, retrying, retry };
}
