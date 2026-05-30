// Shared types between the server-side status collector and the client UI.
// IMPORTANT: this file is imported by client components, so it must never
// contain secrets or server-only logic — types only.

export type Health = "up" | "down" | "warn" | "unknown";

export interface ServiceStatus {
  id: string;
  health: Health;
  /** Short human detail, e.g. "v4.0.17" or "connection refused". */
  detail?: string;
}

export interface VpnStatus {
  up: boolean;
  exitIp?: string;
  country?: string;
  city?: string;
  /** True when we could not reach gluetun's control API at all. */
  unknown?: boolean;
}

export interface MullvadStatus {
  /** False when no account number is configured, so expiry is unknown. */
  known: boolean;
  daysLeft?: number;
  expires?: string;
}

export interface StorageStatus {
  known: boolean;
  usedPct?: number;
  freeGb?: number;
  totalGb?: number;
  /** ISO timestamp of the most recent acquisition backup, if found. */
  lastBackup?: string;
  lastBackupAgeHours?: number;
}

export interface ArrHealth {
  warnings: number;
  errors: number;
  messages: string[];
}

export interface StatusReport {
  generatedAt: string;
  services: ServiceStatus[];
  vpn: VpnStatus;
  mullvad: MullvadStatus;
  storage: StorageStatus;
  arr: ArrHealth;
  /** Overall green light: false if any critical check is failing. */
  ok: boolean;
}
