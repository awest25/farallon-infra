"use client";

import { useCallback, useEffect, useState } from "react";
import type { StatusReport } from "./types";

async function fetchStatus(): Promise<StatusReport> {
  const res = await fetch("/api/status", { cache: "no-store" });
  if (!res.ok) throw new Error(`status ${res.status}`);
  return (await res.json()) as StatusReport;
}

/**
 * Polls /api/status on an interval and whenever the tab regains focus, so the
 * directory always reflects live health without a manual refresh.
 */
export function useStatus(intervalMs = 15_000) {
  const [data, setData] = useState<StatusReport | null>(null);
  const [error, setError] = useState(false);
  const [loading, setLoading] = useState(true);

  // Exposed for the manual refresh button.
  const refresh = useCallback(async () => {
    try {
      setData(await fetchStatus());
      setError(false);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    // DECISION: define the fetch inside the effect (rather than calling the
    // hoisted `refresh`) so the React Compiler lint doesn't see a synchronous
    // setState-in-effect; the `cancelled` guard drops responses that resolve
    // after unmount.
    let cancelled = false;
    const load = async () => {
      try {
        const report = await fetchStatus();
        if (cancelled) return;
        setData(report);
        setError(false);
      } catch {
        if (!cancelled) setError(true);
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    load();
    const timer = setInterval(load, intervalMs);
    const onVisible = () => {
      if (!document.hidden) load();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      cancelled = true;
      clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [intervalMs]);

  return { data, error, loading, refresh };
}
