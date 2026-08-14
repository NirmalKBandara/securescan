type ApiProxyLimits = {
  maxRequestBytes: number;
  timeoutMs: number;
};

export type ApiProxyConfig = ApiProxyLimits & (
  | { baseUrl: string; mode: "gateway" }
  | { baseUrl: string; gatewaySecret: string; mode: "direct" }
);

const MAX_REQUEST_BYTES = 4_096;
const MAX_TIMEOUT_MS = 10_000;

function boundedPositiveInteger(
  name: string,
  value: string | undefined,
  fallback: number,
  maximum: number,
) {
  const candidate = value?.trim();
  const parsed = candidate ? Number(candidate) : fallback;
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > maximum) {
    throw new Error(`${name} must be an integer between 1 and ${maximum}`);
  }
  return parsed;
}

function absoluteBaseUrl(name: string, value: string | undefined) {
  const candidate = value?.trim();
  if (!candidate) throw new Error(`${name} is required`);

  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    throw new Error(`${name} must be a valid absolute URL`);
  }

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`${name} must use http or https`);
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error(`${name} must not include credentials, a query, or a fragment`);
  }

  url.pathname = url.pathname.replace(/\/$/, "");
  return url.toString().replace(/\/$/, "");
}

export function loadApiProxyConfig(
  source: Record<string, string | undefined> = process.env,
): ApiProxyConfig {
  const mode = source.SECURESCAN_API_MODE?.trim() || "gateway";
  const limits = {
    maxRequestBytes: boundedPositiveInteger(
      "API_MAX_REQUEST_BYTES",
      source.API_MAX_REQUEST_BYTES,
      MAX_REQUEST_BYTES,
      MAX_REQUEST_BYTES,
    ),
    timeoutMs: boundedPositiveInteger(
      "API_GATEWAY_TIMEOUT_MS",
      source.API_GATEWAY_TIMEOUT_MS,
      MAX_TIMEOUT_MS,
      MAX_TIMEOUT_MS,
    ),
  };

  if (mode === "gateway") {
    return {
      baseUrl: absoluteBaseUrl(
        "API_MANAGER_GATEWAY_URL",
        source.API_MANAGER_GATEWAY_URL,
      ),
      ...limits,
      mode,
    };
  }

  if (mode === "direct") {
    const gatewaySecret = source.SECURESCAN_API_GATEWAY_SECRET?.trim();
    if (!gatewaySecret || gatewaySecret.length < 32) {
      throw new Error(
        "SECURESCAN_API_GATEWAY_SECRET must contain at least 32 characters",
      );
    }
    return {
      baseUrl: absoluteBaseUrl(
        "BALLERINA_API_BASE_URL",
        source.BALLERINA_API_BASE_URL,
      ),
      gatewaySecret,
      ...limits,
      mode,
    };
  }

  throw new Error('SECURESCAN_API_MODE must be "gateway" or "direct"');
}
