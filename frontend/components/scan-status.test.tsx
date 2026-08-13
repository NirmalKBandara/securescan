import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ScanStatus } from "@/components/scan-status";
import type { ScanHistoryItem, ScanStatus as ScanStatusValue } from "@/lib/api/types";

function scan(status: ScanStatusValue): ScanHistoryItem {
  return {
    id: "scan-status-20",
    status,
    target: "scanme.nmap.org",
    startPort: 20,
    endPort: 25,
    createdAt: "2026-08-11T09:05:04Z",
    updatedAt: "2026-08-11T09:06:07Z",
  };
}

describe("ScanStatus", () => {
  it.each([
    ["queued", "Queued"],
    ["accepted", "Accepted"],
    ["running", "Running"],
    ["completed", "Completed"],
    ["failed", "Failed"],
    ["blocked", "Blocked"],
  ] as const)("renders the %s state", (status, label) => {
    render(<ScanStatus scan={scan(status)} />);

    expect(screen.getByText(label)).toBeVisible();
    expect(screen.getByText("20–25")).toBeVisible();
    expect(screen.getByText("11 Aug 2026, 09:05:04 UTC")).toBeVisible();
  });

  it("shows accessible progress only for active scans", () => {
    const view = render(<ScanStatus scan={scan("running")} />);
    expect(screen.getByRole("progressbar", { name: "running scan progress" })).toHaveAttribute("aria-valuetext", "running");

    view.rerender(<ScanStatus scan={scan("completed")} />);
    expect(screen.queryByRole("progressbar")).not.toBeInTheDocument();
  });
});
