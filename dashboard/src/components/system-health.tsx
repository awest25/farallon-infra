import { Activity, CalendarClock, Clock, HardDrive, Shield } from "lucide-react";
import type { LucideIcon } from "lucide-react";

import { cn } from "@/lib/utils";
import { DEFAULT_DISK_WARN_PCT } from "@/lib/constants";
import type { StatusReport } from "@/lib/types";

type Tone = "ok" | "warn" | "bad" | "muted";

const TONE: Record<Tone, string> = {
  ok: "text-emerald-500",
  warn: "text-amber-500",
  bad: "text-red-500",
  muted: "text-muted-foreground",
};

// At-a-glance tone thresholds. Disk turns red at the shared DEFAULT_DISK_WARN_PCT.
const MULLVAD_CRIT_DAYS = 2;
const MULLVAD_WARN_DAYS = 7;
const DISK_NEAR_FULL_PCT = 80;
const BACKUP_OK_HOURS = 30;
const BACKUP_WARN_HOURS = 50;

function StatCard({
  icon: Icon,
  label,
  value,
  sub,
  tone,
}: {
  icon: LucideIcon;
  label: string;
  value: string;
  sub?: string;
  tone: Tone;
}) {
  return (
    <div className="flex flex-col gap-1 rounded-xl border bg-card p-4">
      <div className="flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        <Icon className={cn("size-3.5", TONE[tone])} />
        {label}
      </div>
      <div className={cn("font-heading text-xl font-semibold tabular-nums", TONE[tone])}>
        {value}
      </div>
      {sub && <div className="truncate text-xs text-muted-foreground">{sub}</div>}
    </div>
  );
}

function Loading() {
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="h-[88px] animate-pulse rounded-xl border bg-card" />
      ))}
    </div>
  );
}

export function SystemHealth({
  data,
  loading,
}: {
  data: StatusReport | null;
  loading: boolean;
}) {
  if (loading && !data) return <Loading />;
  if (!data) return null;

  const { vpn, mullvad, storage, arr } = data;

  // VPN
  const vpnTone: Tone = vpn.up ? "ok" : vpn.unknown ? "warn" : "bad";
  const vpnValue = vpn.up ? "Protected" : vpn.unknown ? "Unknown" : "VPN DOWN";
  const vpnSub = vpn.up
    ? [vpn.city, vpn.country].filter(Boolean).join(", ") || vpn.exitIp
    : "Downloads are blocked";

  // Mullvad expiry
  const mTone: Tone = !mullvad.known
    ? "muted"
    : (mullvad.daysLeft ?? 0) <= MULLVAD_CRIT_DAYS
      ? "bad"
      : (mullvad.daysLeft ?? 0) <= MULLVAD_WARN_DAYS
        ? "warn"
        : "ok";
  const mValue = mullvad.known ? `${mullvad.daysLeft}d left` : "—";
  const mSub = mullvad.known
    ? mullvad.expires
      ? `expires ${new Date(mullvad.expires).toLocaleDateString()}`
      : undefined
    : "set MULLVAD_ACCOUNT_NUMBER";

  // Disk
  const dPct = storage.usedPct ?? 0;
  const dTone: Tone = !storage.known
    ? "muted"
    : dPct >= DEFAULT_DISK_WARN_PCT
      ? "bad"
      : dPct >= DISK_NEAR_FULL_PCT
        ? "warn"
        : "ok";
  const dValue = storage.known ? `${dPct}% used` : "—";
  const dSub = storage.known ? `${storage.freeGb} GB free of ${storage.totalGb} GB` : "no mount";

  // Backups
  const age = storage.lastBackupAgeHours;
  const bTone: Tone =
    age === undefined
      ? "muted"
      : age <= BACKUP_OK_HOURS
        ? "ok"
        : age <= BACKUP_WARN_HOURS
          ? "warn"
          : "bad";
  const bValue = age === undefined ? "—" : age < 1 ? "<1h ago" : `${age}h ago`;
  const bSub = storage.lastBackup
    ? `last ${new Date(storage.lastBackup).toLocaleDateString()}`
    : "no backups found";

  // Indexers / app health
  const hTone: Tone = arr.errors > 0 ? "bad" : arr.warnings > 0 ? "warn" : "ok";
  const hValue =
    arr.errors > 0
      ? `${arr.errors} error${arr.errors > 1 ? "s" : ""}`
      : arr.warnings > 0
        ? `${arr.warnings} warning${arr.warnings > 1 ? "s" : ""}`
        : "All healthy";
  const hSub = arr.messages[0] ?? "Sonarr · Radarr · Prowlarr";

  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
      <StatCard icon={Shield} label="VPN" value={vpnValue} sub={vpnSub} tone={vpnTone} />
      <StatCard icon={CalendarClock} label="Mullvad" value={mValue} sub={mSub} tone={mTone} />
      <StatCard icon={HardDrive} label="Storage" value={dValue} sub={dSub} tone={dTone} />
      <StatCard icon={Clock} label="Last backup" value={bValue} sub={bSub} tone={bTone} />
      <StatCard icon={Activity} label="Automation" value={hValue} sub={hSub} tone={hTone} />
    </div>
  );
}
