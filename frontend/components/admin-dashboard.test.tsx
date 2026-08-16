import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { AdminDashboard } from "./admin-dashboard";
import { adminApi } from "@/lib/api/client";

vi.mock("@/lib/api/client", async (loadOriginal) => {
  const original = await loadOriginal<typeof import("@/lib/api/client")>();
  return { ...original, adminApi: {
    usage: vi.fn(), scans: vi.fn(), auditLogs: vi.fn(), allowedTargets: vi.fn(),
    createAllowedTarget: vi.fn(), disableAllowedTarget: vi.fn(),
  } };
});

const usage = { totalUsers: 2, totalScans: 3, queuedScans: 0, runningScans: 1,
  completedScans: 0, failedScans: 1, blockedScans: 1, enabledAllowedTargets: 1 };

describe("AdminDashboard", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(adminApi.usage).mockResolvedValue(usage);
    vi.mocked(adminApi.scans).mockResolvedValue({ pageSize: 100, items: [{
      id: "scan-1", ownerSubject: "alice", target: "blocked.example", startPort: 1,
      endPort: 10, status: "blocked", failureCode: "BLOCKED_TARGET",
      createdAt: "2026-08-16T10:00:00Z", updatedAt: "2026-08-16T10:00:01Z",
    }] });
    vi.mocked(adminApi.auditLogs).mockResolvedValue({ pageSize: 100, items: [{
      id: "event-1", occurredAt: "2026-08-16T10:00:01Z", actorType: "SERVICE",
      actorSubject: "securescan-api", ownerSubject: "alice", action: "SCAN_BLOCKED",
      outcome: "DENIED", metadata: { failureCode: "BLOCKED_TARGET" },
    }] });
    vi.mocked(adminApi.allowedTargets).mockResolvedValue({ pageSize: 100, items: [{
      id: "target-1", targetKind: "HOSTNAME", target: "scan.example.com", enabled: true,
      createdBySubject: "admin", createdAt: "2026-08-16T09:00:00Z",
      updatedAt: "2026-08-16T09:00:00Z",
    }] });
  });

  it("shows cross-user blocked scans, target controls, and audit events", async () => {
    render(<AdminDashboard />);
    expect(await screen.findByText("BLOCKED_TARGET")).toBeInTheDocument();
    expect(screen.getAllByText("alice")).toHaveLength(2);
    expect(screen.getByRole("button", { name: "Disable" })).toBeInTheDocument();
    expect(screen.getByText("SCAN_BLOCKED")).toBeInTheDocument();
  });

  it("sends user and status filters to the admin scans API", async () => {
    const user = userEvent.setup();
    render(<AdminDashboard />);
    await screen.findByText("BLOCKED_TARGET");
    await user.type(screen.getByLabelText("User subject"), "alice");
    await user.selectOptions(screen.getByLabelText("Status"), "blocked");
    await user.click(screen.getByRole("button", { name: "Apply filters" }));
    await waitFor(() => expect(adminApi.scans).toHaveBeenLastCalledWith({
      ownerSubject: "alice", status: "blocked",
    }));
  });

  it("creates a bounded allowed target", async () => {
    const user = userEvent.setup();
    vi.mocked(adminApi.createAllowedTarget).mockResolvedValue({
      id: "target-2", targetKind: "HOSTNAME", target: "public.example",
      startPort: 443, endPort: 443, enabled: true, createdBySubject: "admin",
      createdAt: "2026-08-16T10:00:00Z", updatedAt: "2026-08-16T10:00:00Z",
    });
    render(<AdminDashboard />);
    await screen.findByText("BLOCKED_TARGET");
    await user.type(screen.getByLabelText("Target"), "public.example");
    await user.type(screen.getByLabelText("Start port"), "443");
    await user.type(screen.getByLabelText("End port"), "443");
    await user.click(screen.getByRole("button", { name: "Add target" }));
    await waitFor(() => expect(adminApi.createAllowedTarget).toHaveBeenCalledWith({
      targetKind: "HOSTNAME", target: "public.example", startPort: 443, endPort: 443,
    }));
  });

  it("rejects an incomplete port policy before calling the API", async () => {
    const user = userEvent.setup();
    render(<AdminDashboard />);
    await screen.findByText("BLOCKED_TARGET");
    await user.type(screen.getByLabelText("Target"), "public.example");
    await user.type(screen.getByLabelText("Start port"), "443");
    await user.click(screen.getByRole("button", { name: "Add target" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Provide both");
    expect(adminApi.createAllowedTarget).not.toHaveBeenCalled();
  });
});
