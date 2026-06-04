// Shared, client-safe constants. No secrets, no server-only imports — this is
// imported by both the server status collector and client components.

/**
 * Storage usage percentage at which the dashboard flips red. Used as the
 * default for the server's DISK_WARN_PCT env override (status.ts) and as the
 * threshold the client UI compares against (system-health, directory-live).
 */
export const DEFAULT_DISK_WARN_PCT = 92;
