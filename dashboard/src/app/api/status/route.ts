import { getStatus } from "@/lib/status";

// Live health — never prerender or cache at the framework level. The collector
// has its own short in-memory cache to protect the backing services.
export const dynamic = "force-dynamic";

export async function GET() {
  const report = await getStatus();
  return Response.json(report, {
    headers: { "Cache-Control": "no-store, max-age=0" },
  });
}
