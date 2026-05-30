// The app catalog — the single source of truth for what shows up in the
// directory. Client-safe: public links + friendly descriptions only. Anything
// that needs a secret (health URLs, API keys) lives server-side in status.ts,
// keyed by the same `id`.

export type Category = "Media" | "Requests" | "Automation" | "Downloads";

export interface AppDef {
  id: string;
  name: string;
  /** Plain-English "what is this for", written so a friend gets it. */
  description: string;
  /** Public URL. Built from NEXT_PUBLIC_DOMAIN at module load. */
  href: string;
  category: Category;
  /** Admin tools are grouped separately so friends know what's for them. */
  admin?: boolean;
}

// DECISION: derive public URLs from NEXT_PUBLIC_DOMAIN instead of hardcoding,
// so the same build works if the domain ever changes.
const DOMAIN = process.env.NEXT_PUBLIC_DOMAIN ?? "alexanderwest.com";
const sub = (s: string) => `https://${s}.${DOMAIN}`;

export const APPS: AppDef[] = [
  {
    id: "jellyfin",
    name: "Jellyfin",
    description:
      "Watch the movie & TV library — our own private Netflix. Sign in and press play on any device.",
    href: sub("jellyfin"),
    category: "Media",
  },
  {
    id: "requests",
    name: "Requests",
    description:
      "Want a movie or show that isn't here yet? Search for it, hit request, and it gets downloaded and added to Jellyfin automatically.",
    href: sub("requests"),
    category: "Requests",
  },
  {
    id: "sonarr",
    name: "Sonarr",
    description:
      "The brain for TV: watches for new episodes of monitored shows and grabs them automatically.",
    href: sub("sonarr"),
    category: "Automation",
    admin: true,
  },
  {
    id: "radarr",
    name: "Radarr",
    description:
      "The brain for movies: finds and downloads monitored films at the quality you want.",
    href: sub("radarr"),
    category: "Automation",
    admin: true,
  },
  {
    id: "prowlarr",
    name: "Prowlarr",
    description:
      "Manages the indexers (where Sonarr and Radarr search). Add or fix a tracker here.",
    href: sub("prowlarr"),
    category: "Automation",
    admin: true,
  },
  {
    id: "qbittorrent",
    name: "qBittorrent",
    description:
      "The download client that actually pulls the files — routed entirely through the Mullvad VPN.",
    href: sub("qbit"),
    category: "Downloads",
    admin: true,
  },
];

export const CATEGORY_ORDER: Category[] = [
  "Media",
  "Requests",
  "Automation",
  "Downloads",
];
