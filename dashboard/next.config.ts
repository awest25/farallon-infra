import type { NextConfig } from "next";
import path from "node:path";

const nextConfig: NextConfig = {
  // Produce a self-contained server bundle for a minimal Docker image.
  output: "standalone",
  // A stray lockfile in a parent dir confuses workspace-root inference; pin it
  // to this app so file tracing (for standalone output) stays correct.
  turbopack: {
    root: path.resolve("."),
  },
};

export default nextConfig;
