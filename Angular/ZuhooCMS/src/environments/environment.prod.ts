// Used by `ng build` (the `production` configuration, which is the build target's default) via the
// fileReplacements entry in angular.json. `ng serve` keeps environment.ts (localhost:8085) and
// `--configuration gateway` keeps environment.gateway.ts (localhost:8090); neither is affected by this file.
//
// THE PRODUCTION API URL LIVES HERE, in one place, and can also be changed after the build:
//
//   1. Default: same origin as the page, path /api. nginx.conf in this project proxies /api/ to the
//      backend, so a build dropped behind that config needs no edit and no per-environment rebuild.
//   2. Override without rebuilding: uncomment the window.ZUHOO_API_URL line in src/index.html (or
//      inject it from the container's entrypoint) when the API is on its own host, e.g. the
//      https://api.zuhoo.app/ host the Android prod flavour uses -> 'https://api.zuhoo.app/api'.
//
// It must be absolute, not a bare '/api': ChatSocketService derives the STOMP brokerURL from it by
// swapping http->ws, and SecureFileService derives the file origin from it. Both need a scheme+host.

declare global {
  interface Window {
    ZUHOO_API_URL?: string;
  }
}

/** Path the API is served under, appended to the page's own origin when there is no override. */
const API_PATH = '/api';

function resolveApiUrl(): string {
  const override = (typeof window !== 'undefined' && window.ZUHOO_API_URL || '').trim();
  const url = override || (typeof window !== 'undefined' ? window.location.origin + API_PATH : API_PATH);
  // A trailing slash would turn every request path into a double slash and break the /api suffix
  // matching in SecureFileService and ChatSocketService.
  return url.replace(/\/+$/, '');
}

export const environment = {
  production: true,
  apiUrl: resolveApiUrl(),
};
