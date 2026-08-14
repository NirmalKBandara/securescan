export type ApiProxyConfig =
  | { baseUrl: string; mode: "gateway" }
  | { baseUrl: string; gatewaySecret: string; mode: "direct" };

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

  if (mode === "gateway") {
    return {
      baseUrl: absoluteBaseUrl(
        "API_MANAGER_GATEWAY_URL",
        source.API_MANAGER_GATEWAY_URL,
      ),
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
      mode,
    };
  }

  throw new Error('SECURESCAN_API_MODE must be "gateway" or "direct"');
}
