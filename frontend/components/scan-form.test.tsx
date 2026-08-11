import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ScanForm } from "./scan-form";
import { scansApi, SecureScanApiError } from "@/lib/api/client";

const push = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push }),
}));

vi.mock("@/lib/api/client", async (importActual) => {
  const actual = await importActual<typeof import("@/lib/api/client")>();
  return {
    ...actual,
    scansApi: { ...actual.scansApi, create: vi.fn() },
  };
});

const createScan = vi.mocked(scansApi.create);

async function completeValidForm() {
  const user = userEvent.setup();
  await user.type(screen.getByLabelText("Target hostname or IP address"), "scanme.nmap.org");
  await user.click(screen.getByLabelText(/I confirm that I own this target/));
  return user;
}

describe("ScanForm", () => {
  beforeEach(() => {
    createScan.mockReset();
    push.mockReset();
  });

  it("shows client validation and does not submit invalid input", async () => {
    const user = userEvent.setup();
    render(<ScanForm />);

    await user.type(screen.getByLabelText("Target hostname or IP address"), "https://example.com/path");
    await user.clear(screen.getByLabelText("Start port"));
    await user.type(screen.getByLabelText("Start port"), "70000");
    await user.click(screen.getByRole("button", { name: "Submit scan" }));

    expect(await screen.findByText("Enter a valid hostname or IP address")).toBeVisible();
    expect(screen.getByText("Port must be between 1 and 65535")).toBeVisible();
    expect(screen.getByText("Confirm that you are authorized to scan this target")).toBeVisible();
    expect(createScan).not.toHaveBeenCalled();
  });

  it("submits normalized values and redirects to the created scan", async () => {
    createScan.mockResolvedValue({
      id: "scan/id",
      status: "queued",
      target: "scanme.nmap.org",
      startPort: 1,
      endPort: 100,
    });
    render(<ScanForm />);
    const user = await completeValidForm();

    await user.click(screen.getByRole("button", { name: "Submit scan" }));

    await waitFor(() => expect(createScan).toHaveBeenCalledWith({
      target: "scanme.nmap.org",
      startPort: 1,
      endPort: 100,
      authorized: true,
    }));
    expect(push).toHaveBeenCalledWith("/scans/scan%2Fid");
  });

  it("displays Ballerina validation errors and their request ID", async () => {
    createScan.mockRejectedValue(new SecureScanApiError(
      "The target is not permitted",
      400,
      "BLOCKED_TARGET",
      "req-day-18",
    ));
    render(<ScanForm />);
    const user = await completeValidForm();

    await user.click(screen.getByRole("button", { name: "Submit scan" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("The target is not permitted");
    expect(screen.getByRole("alert")).toHaveTextContent("Request ID: req-day-18");
    expect(push).not.toHaveBeenCalled();
  });
});
