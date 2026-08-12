import { StrictMode } from "react";
import { act, fireEvent, render, screen } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ScanDetailView } from "@/components/scan-detail";
import { SCAN_POLL_INTERVAL_MS } from "@/hooks/use-scan-detail";
import { scansApi, SecureScanApiError } from "@/lib/api/client";
import type { ScanDetail, ScanStatus } from "@/lib/api/types";

vi.mock("@/lib/api/client", async (importActual) => {
  const actual = await importActual<typeof import("@/lib/api/client")>();
  return {
    ...actual,
    scansApi: { ...actual.scansApi, get: vi.fn() },
  };
});

const getScan = vi.mocked(scansApi.get);

function scan(status: ScanStatus, overrides: Partial<ScanDetail> = {}): ScanDetail {
  return {
    id: "scan-19",
    status,
    target: "scanme.nmap.org",
    startPort: 22,
    endPort: 443,
    createdAt: "2026-08-12T10:00:00Z",
    updatedAt: "2026-08-12T10:00:02Z",
    ...overrides,
  };
}

async function flushRequest() {
  await act(async () => undefined);
}

describe("ScanDetailView", () => {
  beforeEach(() => {
    getScan.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("fetches and renders completed scan timestamps and open and closed ports", async () => {
    getScan.mockResolvedValue(scan("completed", {
      result: {
        target: "scanme.nmap.org",
        startPort: 22,
        endPort: 443,
        durationNanos: 1_500_000,
        results: [
          { address: "45.33.32.156", port: 22, state: "open" },
          { address: "45.33.32.156", port: 443, state: "closed" },
        ],
      },
    }));

    render(<ScanDetailView id="scan/id" />);

    expect(screen.getByRole("status")).toHaveTextContent("Loading scan details");
    expect(await screen.findByRole("heading", { name: "scanme.nmap.org" })).toBeVisible();
    expect(getScan).toHaveBeenCalledWith("scan/id", { signal: expect.any(AbortSignal) });
    expect(screen.getAllByText("45.33.32.156")).toHaveLength(2);
    expect(screen.getByText("22")).toBeVisible();
    expect(screen.getByText("443")).toBeVisible();
    expect(screen.getByText("open")).toBeVisible();
    expect(screen.getByText("closed")).toBeVisible();
    expect(screen.getByText("2 results")).toBeVisible();
    expect(document.querySelector('time[datetime="2026-08-12T10:00:00Z"]')).toBeInTheDocument();
    expect(document.querySelector('time[datetime="2026-08-12T10:00:02Z"]')).toBeInTheDocument();
  });

  it("polls active states in sequence and stops after completion", async () => {
    vi.useFakeTimers();
    getScan
      .mockResolvedValueOnce(scan("queued"))
      .mockResolvedValueOnce(scan("running"))
      .mockResolvedValueOnce(scan("completed", {
        result: {
          target: "scanme.nmap.org",
          startPort: 22,
          endPort: 443,
          durationNanos: 2_000_000,
          results: [{ address: "45.33.32.156", port: 443, state: "open" }],
        },
      }));

    render(<ScanDetailView id="scan-19" />);
    await flushRequest();
    expect(screen.getByText("Queued")).toBeVisible();

    await act(() => vi.advanceTimersByTimeAsync(SCAN_POLL_INTERVAL_MS));
    expect(screen.getByText("Running")).toBeVisible();

    await act(() => vi.advanceTimersByTimeAsync(SCAN_POLL_INTERVAL_MS));
    expect(screen.getByText("Completed")).toBeVisible();
    expect(screen.getByText("open")).toBeVisible();

    await act(() => vi.advanceTimersByTimeAsync(SCAN_POLL_INTERVAL_MS * 3));
    expect(getScan).toHaveBeenCalledTimes(3);
  });

  it.each([
    ["failed" as const, "SCANNER_UNAVAILABLE", "The scanner service was unavailable.", "Scan unsuccessful"],
    ["blocked" as const, "BLOCKED_TARGET", "The target was blocked by the network safety policy.", "Target blocked"],
  ])("renders the %s reason and does not poll again", async (status, failureCode, reason, heading) => {
    vi.useFakeTimers();
    getScan.mockResolvedValue(scan(status, { failureCode }));

    render(<ScanDetailView id="scan-19" />);
    await flushRequest();

    expect(screen.getByRole("heading", { name: heading })).toBeVisible();
    expect(screen.getByText(reason)).toBeVisible();
    await act(() => vi.advanceTimersByTimeAsync(SCAN_POLL_INTERVAL_MS * 2));
    expect(getScan).toHaveBeenCalledTimes(1);
  });

  it("automatically retries a temporary fetch failure", async () => {
    vi.useFakeTimers();
    getScan
      .mockRejectedValueOnce(new SecureScanApiError("Scanner unavailable", 503, "SCANNER_UNAVAILABLE", "req-19"))
      .mockResolvedValueOnce(scan("completed", { result: null }));

    render(<ScanDetailView id="scan-19" />);
    await flushRequest();
    expect(screen.getByRole("alert")).toHaveTextContent("Scanner unavailable");
    expect(screen.getByRole("alert")).toHaveTextContent("req-19");

    await act(() => vi.advanceTimersByTimeAsync(SCAN_POLL_INTERVAL_MS));
    expect(screen.getByText("Completed")).toBeVisible();
    expect(getScan).toHaveBeenCalledTimes(2);
  });

  it("clears the scheduled automatic retry when retrying manually", async () => {
    vi.useFakeTimers();
    getScan
      .mockRejectedValueOnce(new SecureScanApiError("Scanner unavailable", 503))
      .mockResolvedValueOnce(scan("completed", { result: null }));

    render(<ScanDetailView id="scan-19" />);
    await flushRequest();
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));
    await flushRequest();
    expect(screen.getByText("Completed")).toBeVisible();

    await act(() => vi.advanceTimersByTimeAsync(SCAN_POLL_INTERVAL_MS * 2));
    expect(getScan).toHaveBeenCalledTimes(2);
  });

  it("clears polling when unmounted", async () => {
    vi.useFakeTimers();
    getScan.mockResolvedValue(scan("running"));
    const view = render(<ScanDetailView id="scan-19" />);
    await flushRequest();
    view.unmount();
    await act(() => vi.advanceTimersByTimeAsync(SCAN_POLL_INTERVAL_MS * 2));
    expect(getScan).toHaveBeenCalledTimes(1);
  });

  it("aborts an in-flight request when unmounted", () => {
    getScan.mockReturnValue(new Promise<ScanDetail>(() => undefined));
    const view = render(<ScanDetailView id="scan-19" />);
    const signal = getScan.mock.calls[0][1]?.signal;

    view.unmount();

    expect(signal?.aborted).toBe(true);
  });

  it("starts a fresh request during the Strict Mode effect replay", async () => {
    const firstRequest = new Promise<ScanDetail>(() => undefined);
    getScan
      .mockReturnValueOnce(firstRequest)
      .mockResolvedValueOnce(scan("completed", { result: null }));

    render(<StrictMode><ScanDetailView id="scan-19" /></StrictMode>);

    expect(await screen.findByText("Completed")).toBeVisible();
    expect(getScan).toHaveBeenCalledTimes(2);
    expect(getScan.mock.calls[0][1]?.signal?.aborted).toBe(true);
  });

  it("abandons an old request when the scan id changes", async () => {
    getScan
      .mockReturnValueOnce(new Promise<ScanDetail>(() => undefined))
      .mockResolvedValueOnce(scan("completed", { id: "scan-20", target: "next.example.com", result: null }));
    const view = render(<ScanDetailView id="scan-19" />);
    const oldSignal = getScan.mock.calls[0][1]?.signal;

    view.rerender(<ScanDetailView id="scan-20" />);

    expect(await screen.findByRole("heading", { name: "next.example.com" })).toBeVisible();
    expect(oldSignal?.aborted).toBe(true);
    expect(getScan.mock.calls.map(([id]) => id)).toEqual(["scan-19", "scan-20"]);
  });
});
