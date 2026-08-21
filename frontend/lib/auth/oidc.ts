import "server-only";

import * as client from "openid-client";
import { loadOidcConfig, type OidcClientKind } from "./config";

const cachedConfigurations = new Map<OidcClientKind, Promise<client.Configuration>>();

export function getOidcConfiguration(clientKind: OidcClientKind = "user") {
  let configuration = cachedConfigurations.get(clientKind);
  if (!configuration) {
    const config = loadOidcConfig(process.env, clientKind);
    configuration = client.discovery(
      config.issuer,
      config.clientId,
      config.clientSecret,
    ).catch((error: unknown) => {
      cachedConfigurations.delete(clientKind);
      throw error;
    });
    cachedConfigurations.set(clientKind, configuration);
  }
  return configuration;
}

export { client };
