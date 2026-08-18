export async function register() {
  if (process.env.NEXT_RUNTIME !== "nodejs") return;

  const [{ loadApiProxyConfig }, { loadOidcConfig }] = await Promise.all([
    import("@/lib/api/proxy-config"),
    import("@/lib/auth/config-values"),
  ]);

  loadApiProxyConfig();
  loadOidcConfig();
}
