import { PenLine } from "lucide-react";

// DECISION: keep the personal copy here as obvious, easily-editable placeholders
// rather than inventing biography details. Swap the tagline/links when ready.
const TAGLINE =
  "My corner of the internet — software, a home lab I tinker with, and (soon) writing.";

export default function Home() {
  return (
    <main className="flex flex-1 items-center justify-center px-6 py-16">
      <div className="flex w-full max-w-xl flex-col items-start gap-8">
        <div className="flex flex-col gap-4">
          <span className="font-mono text-xs uppercase tracking-[0.2em] text-muted-foreground">
            alexanderwest.com
          </span>
          <h1 className="font-heading text-5xl font-bold tracking-tight sm:text-6xl">
            Alex West
          </h1>
          <p className="max-w-md text-lg leading-relaxed text-muted-foreground">
            {TAGLINE}
          </p>
        </div>

        {/* DECISION: no link to /directory here — that page + its /api/status feed
            are gated to LAN/VPN only (they expose VPN exit IP, Mullvad expiry,
            storage/backup figures, *arr errors), so a public link would just 403.
            Reach the directory directly by URL when on the LAN or WireGuard. */}
        <div className="flex flex-wrap items-center gap-3">
          <span className="inline-flex cursor-default items-center gap-2 rounded-lg border border-dashed px-5 py-2.5 text-sm text-muted-foreground">
            <PenLine className="size-4" />
            Blog — coming soon
          </span>
        </div>
      </div>
    </main>
  );
}
