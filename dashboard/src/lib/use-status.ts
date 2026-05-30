"use client";

import { useCallback, useEffect, useState } from "react";
import type { StatusReport } from "./types";

/**
 * Polls /api/status on an interval and whenever the tab regains focus, so the
 * directory always reflects live health without a manual refresh.
 */
export function useStatus(intervalMs = 15_000) {
  const [data, setData] = useState<StatusReport | null>(null);
  const [error, setError] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/status", { cache: "no-store" });
      if (!res.ok) throw new Error(`status ${res.status}`);
      setData((await res.json()) as StatusReport);
      setError(false);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
    const timer = setInterval(load, intervalMs);
    const onVisible = () => {
      if (!document.hidden) load();
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [load, intervalMs]);

  return { data, error, loading, refresh: load };
}
