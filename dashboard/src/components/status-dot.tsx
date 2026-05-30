import { cn } from "@/lib/utils";
import type { Health } from "@/lib/types";

const STYLES: Record<Health, { dot: string; ring: string; label: string }> = {
  up: { dot: "bg-emerald-500", ring: "bg-emerald-500/60", label: "Online" },
  warn: { dot: "bg-amber-500", ring: "bg-amber-500/60", label: "Degraded" },
  down: { dot: "bg-red-500", ring: "bg-red-500/60", label: "Offline" },
  unknown: { dot: "bg-muted-foreground", ring: "bg-muted-foreground/40", label: "Unknown" },
};

export function StatusDot({
  health,
  pulse = true,
  className,
}: {
  health: Health;
  pulse?: boolean;
  className?: string;
}) {
  const s = STYLES[health];
  return (
    <span className={cn("relative inline-flex size-2.5 shrink-0", className)} aria-label={s.label}>
      {pulse && health !== "unknown" && (
        <span
          className={cn(
            "absolute inline-flex h-full w-full animate-ping rounded-full opacity-75",
            s.ring,
          )}
        />
      )}
      <span className={cn("relative inline-flex size-2.5 rounded-full", s.dot)} />
    </span>
  );
}

export function healthLabel(health: Health): string {
  return STYLES[health].label;
}
