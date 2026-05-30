import { ArrowUpRight } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { StatusDot, healthLabel } from "@/components/status-dot";
import { cn } from "@/lib/utils";
import type { AppDef } from "@/lib/apps";
import type { Health } from "@/lib/types";

export function AppCard({
  app,
  health,
  detail,
}: {
  app: AppDef;
  health: Health;
  detail?: string;
}) {
  return (
    <a
      href={app.href}
      target="_blank"
      rel="noreferrer"
      className={cn(
        "group relative flex flex-col gap-3 rounded-xl border bg-card p-5 transition-all",
        "hover:border-foreground/20 hover:bg-accent/40 hover:shadow-lg hover:shadow-black/5",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
      )}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-center gap-2">
          <h3 className="font-heading text-lg font-semibold tracking-tight">{app.name}</h3>
          {app.admin && (
            <Badge variant="outline" className="text-[10px] uppercase tracking-wide">
              admin
            </Badge>
          )}
        </div>
        <ArrowUpRight className="size-4 text-muted-foreground transition-transform group-hover:-translate-y-0.5 group-hover:translate-x-0.5" />
      </div>

      <p className="text-sm leading-relaxed text-muted-foreground">{app.description}</p>

      <div className="mt-auto flex items-center gap-2 pt-1 text-xs text-muted-foreground">
        <StatusDot health={health} />
        <span className={cn(health === "down" && "text-red-500")}>
          {healthLabel(health)}
          {health === "down" && detail ? ` · ${detail}` : ""}
        </span>
      </div>
    </a>
  );
}
