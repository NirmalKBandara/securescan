import { z } from "zod";

const PORT_MIN = 1;
const PORT_MAX = 65_535;
const MAX_PORTS_PER_SCAN = 1_000;

function isIpv4(value: string) {
  const octets = value.split(".");
  return octets.length === 4 && octets.every((octet) => {
    if (!/^\d{1,3}$/.test(octet) || (octet.length > 1 && octet.startsWith("0"))) return false;
    const number = Number(octet);
    return number >= 0 && number <= 255;
  });
}

function isIpv6(value: string) {
  if (!value.includes(":")) return false;
  try {
    const parsed = new URL(`http://[${value}]/`);
    return parsed.hostname.startsWith("[") && parsed.hostname.endsWith("]");
  } catch {
    return false;
  }
}

function isHostname(value: string) {
  if (value.length > 253) return false;
  const hostname = value.endsWith(".") ? value.slice(0, -1) : value;
  const labels = hostname.split(".");
  return labels.length > 0 && labels.every((label) =>
    label.length > 0 &&
    label.length <= 63 &&
    /^[a-z\d](?:[a-z\d-]*[a-z\d])?$/i.test(label),
  );
}

export function isScanTarget(value: string) {
  if (/^[\d.]+$/.test(value)) return isIpv4(value);
  return isIpv6(value) || isHostname(value);
}

const portSchema = z.number({ error: "Enter a whole-number port" })
  .int("Enter a whole-number port")
  .min(PORT_MIN, `Port must be between ${PORT_MIN} and ${PORT_MAX}`)
  .max(PORT_MAX, `Port must be between ${PORT_MIN} and ${PORT_MAX}`);

export const scanFormSchema = z.object({
  target: z.string()
    .trim()
    .min(1, "Enter a target hostname or IP address")
    .refine(isScanTarget, "Enter a valid hostname or IP address"),
  startPort: portSchema,
  endPort: portSchema,
  authorized: z.boolean().refine(Boolean, {
    message: "Confirm that you are authorized to scan this target",
  }),
}).superRefine(({ startPort, endPort }, context) => {
  if (startPort > endPort) {
    context.addIssue({
      code: "custom",
      path: ["endPort"],
      message: "End port must be greater than or equal to start port",
    });
  } else if (endPort - startPort + 1 > MAX_PORTS_PER_SCAN) {
    context.addIssue({
      code: "custom",
      path: ["endPort"],
      message: `A scan can include at most ${MAX_PORTS_PER_SCAN} ports`,
    });
  }
});

export type ScanFormValues = z.infer<typeof scanFormSchema>;
