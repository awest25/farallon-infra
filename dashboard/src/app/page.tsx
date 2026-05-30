import Link from "next/link";
import { ArrowRight, PenLine } from "lucide-react";

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

        <div className="flex flex-wrap items-center gap-3">
          <Link
            href="/directory"
            className="group inline-flex items-center gap-2 rounded-lg bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
          >
            Explore the directory
            <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
          </Link>

          <span className="inline-flex cursor-default items-center gap-2 rounded-lg border border-dashed px-5 py-2.5 text-sm text-muted-foreground">
            <PenLine className="size-4" />
            Blog — coming soon
          </span>
        </div>

        <p className="text-sm text-muted-foreground">
          The{" "}
          <Link href="/directory" className="text-foreground underline underline-offset-4">
            directory
          </Link>{" "}
          lists all my self-hosted apps, what each one is for, and whether it&apos;s
          online right now.
        </p>
      </div>
    </main>
  );
}
