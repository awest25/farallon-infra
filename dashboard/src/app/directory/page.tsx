import Link from "next/link";
import { ArrowLeft } from "lucide-react";

import { DirectoryLive } from "@/components/directory-live";

export const metadata = {
  title: "Directory · Alex West",
  description: "All my self-hosted apps, what they do, and live status.",
};

export default function DirectoryPage() {
  return (
    <main className="mx-auto w-full max-w-5xl flex-1 px-6 py-12">
      <header className="mb-10 flex flex-col gap-4">
        <Link
          href="/"
          className="inline-flex w-fit items-center gap-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground"
        >
          <ArrowLeft className="size-4" />
          Alex West
        </Link>
        <div className="flex flex-col gap-2">
          <h1 className="font-heading text-3xl font-bold tracking-tight">Directory</h1>
          <p className="max-w-2xl text-muted-foreground">
            Everything I self-host, what each app is for, and whether it&apos;s online
            right now. Click any card to open it.
          </p>
        </div>
      </header>

      <DirectoryLive />
    </main>
  );
}
