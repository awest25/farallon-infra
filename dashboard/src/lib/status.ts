// Server-only status collector. Holds all secrets (API keys) and does the
// actual health probing against internal LAN services, so the browser only ever
// receives booleans + safe display strings via /api/status.
//
// Never import this from a client component — it reads node:fs and env secrets.

import { promises as fs } from "node:fs";
import path from "node:path";
import type {
  ServiceStatus,
  VpnStatus,
  MullvadStatus,
  StorageStatus,
  ArrHealth,
  StatusReport,
} from "./types";

const env = (k: string, d = "") => process.env[k] ?? d;

// DECISION: default every endpoint to its known LAN address so the dashboard
// works in local dev (on the LAN) even before env vars are wired in the
// container. In production these are overridden via the container's env.
const SVC = {
  jellyfin: env("JELLYFIN_URL", "http://10.0.0.33:8096"),
  requests: env("JELLYSEERR_URL", "http://10.0.0.34:5055"),
  sonarr: env("SONARR_URL", "http://10.0.0.34:8989"),
  radarr: env("RADARR_URL", "http://10.0.0.34:7878"),
  prowlarr: env("PROWLARR_URL", "http://10.0.0.34:9696"),
  qbittorrent: env("QBIT_URL", "http://10.0.0.34:8080"),
};

const KEY = {
  sonarr: env("SONARR_API_KEY"),
  radarr: env("RADARR_API_KEY"),
  prowlarr: env("PROWLARR_API_KEY"),
};

const GLUETUN_URL = env("GLUETUN_URL", "http://10.0.0.34:8000");
const GLUETUN_API_KEY = env("GLUETUN_API_KEY");
const MULLVAD_ACCOUNT = env("MULLVAD_ACCOUNT_NUMBER");
const STORAGE_PATH = env("STORAGE_PATH", "/mnt/storage");
const DISK_WARN_PCT = Number(env("DISK_WARN_PCT", "92"));

const TIMEOUT_MS = 4000;

async function fetchT(
  url: string,
  init: (RequestInit & { timeout?: number }) | undefined = undefined,
) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), init?.timeout ?? TIMEOUT_MS);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal, cache: "no-store" });
  } finally {
    clearTimeout(timer);
  }
}

/** A service is "up" if it answers HTTP at all (even 401/403 = it's alive). */
async function reachable(
  url: string,
  init?: RequestInit,
): Promise<{ up: boolean; detail?: string }> {
  try {
    const res = await fetchT(url, init);
    if (res.status >= 500) return { up: true, detail: `HTTP ${res.status}` };
    return { up: true };
  } catch (e) {
    const name = (e as Error)?.name;
    return { up: false, detail: name === "AbortError" ? "timeout" : "unreachable" };
  }
}

// Per-service probes. qBittorrent answers 403 unauthenticated, which still
// proves it's alive, so reachable() is the right check for all of them.
const PROBES: Record<string, () => Promise<{ up: boolean; detail?: string }>> = {
  jellyfin: () => reachable(`${SVC.jellyfin}/health`),
  requests: () => reachable(`${SVC.requests}/api/v1/status`),
  sonarr: () => reachable(`${SVC.sonarr}/ping`),
  radarr: () => reachable(`${SVC.radarr}/ping`),
  prowlarr: () => reachable(`${SVC.prowlarr}/ping`),
  qbittorrent: () => reachable(`${SVC.qbittorrent}/api/v2/app/version`),
};

async function checkServices(): Promise<ServiceStatus[]> {
  const ids = Object.keys(PROBES);
  return Promise.all(
    ids.map(async (id) => {
      const r = await PROBES[id]();
      return { id, health: r.up ? "up" : "down", detail: r.detail } as ServiceStatus;
    }),
  );
}

async function checkVpn(): Promise<VpnStatus> {
  try {
    const res = await fetchT(`${GLUETUN_URL}/v1/publicip/ip`, {
      headers: GLUETUN_API_KEY ? { "X-API-Key": GLUETUN_API_KEY } : undefined,
    });
    if (!res.ok) {
      // 401/403 means gluetun is up but auth is misconfigured — treat as unknown
      return { up: false, unknown: res.status === 401 || res.status === 403 };
    }
    const d = (await res.json()) as {
      public_ip?: string;
      ip?: string;
      country?: string;
      city?: string;
    };
    const ip = d.public_ip || d.ip;
    return { up: Boolean(ip), exitIp: ip, country: d.country, city: d.city };
  } catch {
    return { up: false, unknown: true };
  }
}

async function checkMullvad(): Promise<MullvadStatus> {
  if (!MULLVAD_ACCOUNT) return { known: false };
  try {
    const res = await fetchT(
      `https://api.mullvad.net/public/accounts/v1/${MULLVAD_ACCOUNT}/`,
      { timeout: 6000 },
    );
    if (!res.ok) return { known: false };
    const d = (await res.json()) as { expiry?: string };
    if (!d.expiry) return { known: false };
    const daysLeft = Math.floor(
      (new Date(d.expiry).getTime() - Date.now()) / 86_400_000,
    );
    return { known: true, expires: d.expiry, daysLeft };
  } catch {
    return { known: false };
  }
}

async function checkStorage(): Promise<StorageStatus> {
  try {
    const s = await fs.statfs(STORAGE_PATH);
    const total = s.blocks * s.bsize;
    const free = s.bavail * s.bsize; // space available to non-root
    const usedPct = Math.round(((total - free) / total) * 100);

    let lastBackup: string | undefined;
    let lastBackupAgeHours: number | undefined;
    try {
      const dir = path.join(STORAGE_PATH, "backups");
      const files = (await fs.readdir(dir)).filter(
        (f) => f.startsWith("acquisition-") && f.endsWith(".tar.gz"),
      );
      let newest = 0;
      for (const f of files) {
        const st = await fs.stat(path.join(dir, f));
        if (st.mtimeMs > newest) newest = st.mtimeMs;
      }
      if (newest) {
        lastBackup = new Date(newest).toISOString();
        lastBackupAgeHours = Math.round((Date.now() - newest) / 3_600_000);
      }
    } catch {
      // backups dir not mounted / not present — leave undefined
    }

    return {
      known: true,
      usedPct,
      freeGb: Math.round(free / 1e9),
      totalGb: Math.round(total / 1e9),
      lastBackup,
      lastBackupAgeHours,
    };
  } catch {
    return { known: false };
  }
}

async function checkArr(): Promise<ArrHealth> {
  const targets = [
    { url: `${SVC.sonarr}/api/v3/health`, key: KEY.sonarr, name: "Sonarr" },
    { url: `${SVC.radarr}/api/v3/health`, key: KEY.radarr, name: "Radarr" },
    { url: `${SVC.prowlarr}/api/v1/health`, key: KEY.prowlarr, name: "Prowlarr" },
  ];
  let warnings = 0;
  let errors = 0;
  const messages: string[] = [];

  await Promise.all(
    targets.map(async (t) => {
      if (!t.key) return;
      try {
        const res = await fetchT(t.url, { headers: { "X-Api-Key": t.key } });
        if (!res.ok) return;
        const arr = (await res.json()) as { type: string; message: string }[];
        for (const h of arr) {
          // "New update is available" is informational, not a failure — don't
          // let it flip the dashboard red.
          if (/update is available/i.test(h.message)) continue;
          if (h.type === "error") {
            errors++;
            messages.push(`${t.name}: ${h.message}`);
          } else if (h.type === "warning") {
            warnings++;
            messages.push(`${t.name}: ${h.message}`);
          }
        }
      } catch {
        // app unreachable is already captured by the service probe
      }
    }),
  );

  return { warnings, errors, messages };
}

// Small in-memory cache so many polling clients don't hammer the services.
let cache: { at: number; report: StatusReport } | null = null;
const CACHE_MS = 8000;

export async function getStatus(): Promise<StatusReport> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.report;

  const [services, vpn, mullvad, storage, arr] = await Promise.all([
    checkServices(),
    checkVpn(),
    checkMullvad(),
    checkStorage(),
    checkArr(),
  ]);

  const criticalDown = services.some((s) => s.health === "down") || !vpn.up;
  const diskBad = storage.known && (storage.usedPct ?? 0) >= DISK_WARN_PCT;
  const ok = !criticalDown && !diskBad && arr.errors === 0;

  const report: StatusReport = {
    generatedAt: new Date().toISOString(),
    services,
    vpn,
    mullvad,
    storage,
    arr,
    ok,
  };
  cache = { at: Date.now(), report };
  return report;
}
