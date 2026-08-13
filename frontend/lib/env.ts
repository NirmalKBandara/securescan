function parseApiBaseUrl(name: string, value: string | undefined) {
  const candidate = value?.trim();
  if (!candidate) throw new Error(`${name} is required`);

  if (candidate.startsWith("/") && !candidate.startsWith("//")) {
    return candidate.replace(/\/$/, "");
  }

  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    throw new Error(`${name} must be a root-relative path or valid absolute URL`);
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error(`${name} must use http or https`);
  }
  return url.toString().replace(/\/$/, "");
}

export const env = Object.freeze({
  apiBaseUrl: parseApiBaseUrl(
    "NEXT_PUBLIC_API_BASE_URL",
    process.env.NEXT_PUBLIC_API_BASE_URL,
  ),
  loginUrl: process.env.NEXT_PUBLIC_LOGIN_URL?.trim() || "/dashboard",
});
