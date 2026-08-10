import type { PortResult, ScanHistoryItem, ScanStatus } from "@/lib/api/types";

const statuses: ScanStatus[] = ["queued", "running", "completed", "failed", "blocked"];

export const mockScans: ScanHistoryItem[] = statuses.map((status, index) => ({
  id: `00000000-0000-4000-8000-00000000000${index + 1}`,
  status,
  target: status === "blocked" ? "private.example.test" : `${status}.scanme.example.com`,
  startPort: 20,
  endPort: 443,
  createdAt: `2026-08-08T0${index}:00:00Z`,
  updatedAt: `2026-08-08T0${index}:02:30Z`,
}));

export const mockResults: PortResult[] = [
  { address: "203.0.113.10", port: 22, state: "closed" },
  { address: "203.0.113.10", port: 80, state: "open" },
  { address: "203.0.113.10", port: 443, state: "open" },
];
