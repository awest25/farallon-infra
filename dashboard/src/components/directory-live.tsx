"use client";

import { AlertTriangle, RefreshCw } from "lucide-react";

import { AppCard } from "@/components/app-card";
import { SystemHealth } from "@/components/system-health";
import { cn } from "@/lib/utils";
import { useStatus } from "@/lib/use-status";
import { APPS, CATEGORY_ORDER, type AppDef } from "@/lib/apps";
import { DEFAULT_DISK_WARN_PCT } from "@/lib/constants";
import type { Health, ServiceStatus } from "@/lib/types";

function problems(
  services: ServiceStatus[],
  vpnDown: boolean,
  diskPct: number | undefined,
  errors: number,
): string[] {
  const out: string[] = [];
  if (vpnDown) out.push("VPN tunnel is down — downloads are blocked");
  const offline = services.filter((s) => s.health === "down").map((s) => s.id);
  if (offline.length) out.push(`Offline: ${offline.join(", ")}`);
  if (diskPct !== undefined && diskPct >= DEFAULT_DISK_WARN_PCT)
    out.push(`Storage ${diskPct}% full`);
  if (errors > 0) out.push(`${errors} automation error${errors > 1 ? "s" : ""}`);
  return out;
}

export function DirectoryLive({ apps = APPS }: { apps?: AppDef[] }) {
  const { data, error, loading, refresh } = useStatus();

  const byId = new Map<string, ServiceStatus>(
    (data?.services ?? []).map((s) => [s.id, s]),
  );
  const healthFor = (id: string): Health => byId.get(id)?.health ?? "unknown";

  const banner = data && !data.ok
    ? problems(data.services, !data.vpn.up, data.storage.usedPct, data.arr.errors)
    : [];

  return (
    <div className="flex flex-col gap-8">
      {/* Overall status banner */}
      {banner.length > 0 && (
        <div className="flex items-start gap-3 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm">
          <AlertTriangle className="mt-0.5 size-5 shrink-0 text-red-500" />
          <div className="flex flex-col gap-0.5">
            <span className="font-medium text-red-500">Something needs attention</span>
            <ul className="list-inside list-disc text-muted-foreground">
              {banner.map((p) => (
                <li key={p}>{p}</li>
              ))}
            </ul>
          </div>
        </div>
      )}
      {error && !data && (
        <div className="flex items-center gap-3 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-600 dark:text-amber-500">
          <AlertTriangle className="size-5 shrink-0" />
          Couldn&apos;t load live status. The dashboard backend may be unreachable.
        </div>
      )}

      {/* System health strip */}
      <section className="flex flex-col gap-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium uppercase tracking-wide text-muted-foreground">
            System health
          </h2>
          <button
            onClick={() => refresh()}
            className="inline-flex items-center gap-1.5 text-xs text-muted-foreground transition-colors hover:text-foreground"
          >
            <RefreshCw className={cn("size-3.5", loading && "animate-spin")} />
            {data ? `updated ${new Date(data.generatedAt).toLocaleTimeString()}` : "loading"}
          </button>
        </div>
        <SystemHealth data={data} loading={loading} />
      </section>

      {/* Apps grouped by category */}
      {CATEGORY_ORDER.map((category) => {
        const group = apps.filter((a) => a.category === category);
        if (group.length === 0) return null;
        return (
          <section key={category} className="flex flex-col gap-3">
            <h2 className="text-sm font-medium uppercase tracking-wide text-muted-foreground">
              {category}
            </h2>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {group.map((app) => (
                <AppCard
                  key={app.id}
                  app={app}
                  health={healthFor(app.id)}
                  detail={byId.get(app.id)?.detail}
                />
              ))}
            </div>
          </section>
        );
      })}
    </div>
  );
}
