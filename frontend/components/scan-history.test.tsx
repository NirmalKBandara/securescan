import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ScanHistory } from "@/components/scan-history";
import { scansApi, SecureScanApiError } from "@/lib/api/client";
import type { ScanHistoryItem } from "@/lib/api/types";

vi.mock("@/lib/api/client", async (importActual) => {
  const actual = await importActual<typeof import("@/lib/api/client")>();
  return {
    ...actual,
    scansApi: { ...actual.scansApi, list: vi.fn() },
  };
});

const listScans = vi.mocked(scansApi.list);

const scans: ScanHistoryItem[] = [
  {
    id: "completed/id",
    status: "completed",
    target: "scanme.nmap.org",
    startPort: 22,
    endPort: 443,
    createdAt: "2026-08-11T09:05:04Z",
    updatedAt: "2026-08-11T09:06:04Z",
  },
  {
    id: "blocked-id",
    status: "blocked",
    target: "private.example.test",
    startPort: 1,
    endPort: 100,
    createdAt: "2026-08-10T08:00:00Z",
    updatedAt: "2026-08-10T08:00:01Z",
  },
];

describe("ScanHistory", () => {
  beforeEach(() => {
    listScans.mockReset();
  });

  it("renders durable history with stable UTC timestamps and detail links", async () => {
    listScans.mockResolvedValue({ items: scans, pageSize: 100 });

    render(<ScanHistory />);

    expect(screen.getByRole("status")).toHaveTextContent("Loading scan history");
    expect(await screen.findByRole("heading", { name: "Recent scans" })).toBeVisible();
    expect(listScans).toHaveBeenCalledWith({ pageSize: 100, signal: expect.any(AbortSignal) });
    expect(screen.getByText("11 Aug 2026, 09:05:04 UTC")).toBeVisible();
    expect(screen.getByRole("link", { name: "scanme.nmap.org" })).toHaveAttribute("href", "/scans/completed%2Fid");
    expect(screen.getByRole("link", { name: "View scan for private.example.test" })).toHaveAttribute("href", "/scans/blocked-id");
  });

  it("filters rows by status and explains an empty filter", async () => {
    listScans.mockResolvedValue({ items: scans, pageSize: 100 });
    render(<ScanHistory />);
    await screen.findByText("scanme.nmap.org");

    fireEvent.change(screen.getByLabelText("Filter by status"), { target: { value: "blocked" } });
    expect(screen.queryByText("scanme.nmap.org")).not.toBeInTheDocument();
    expect(screen.getByText("private.example.test")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Filter by status"), { target: { value: "running" } });
    expect(screen.getByRole("status")).toHaveTextContent("No scans match the selected status.");
  });

  it("shows the empty state when no durable jobs exist", async () => {
    listScans.mockResolvedValue({ items: [], pageSize: 100 });
    render(<ScanHistory />);

    expect(await screen.findByRole("heading", { name: "No scan history yet" })).toBeVisible();
    expect(screen.getByRole("link", { name: "Submit your first scan" })).toHaveAttribute("href", "/scans/new");
  });

  it("retries a failed history request", async () => {
    listScans
      .mockRejectedValueOnce(new SecureScanApiError("Database unavailable", 503, "PERSISTENCE_UNAVAILABLE", "req-20"))
      .mockResolvedValueOnce({ items: scans, pageSize: 100 });
    render(<ScanHistory />);

    expect(await screen.findByRole("alert")).toHaveTextContent("Database unavailable");
    expect(screen.getByRole("alert")).toHaveTextContent("req-20");
    fireEvent.click(screen.getByRole("button", { name: "Try again" }));

    await waitFor(() => expect(listScans).toHaveBeenCalledTimes(2));
    expect(await screen.findByText("scanme.nmap.org")).toBeVisible();
  });
});
