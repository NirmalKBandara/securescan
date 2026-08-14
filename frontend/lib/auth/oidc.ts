import "server-only";

import * as client from "openid-client";
import { loadOidcConfig } from "./config";

let cachedConfiguration: Promise<client.Configuration> | undefined;

export function getOidcConfiguration() {
  if (!cachedConfiguration) {
    const config = loadOidcConfig();
    cachedConfiguration = client.discovery(
      config.issuer,
      config.clientId,
      config.clientSecret,
    ).catch((error: unknown) => {
      cachedConfiguration = undefined;
      throw error;
    });
  }
  return cachedConfiguration;
}

export { client };
