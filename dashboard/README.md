# Dashboard

Personal landing page + live status board for the Farallon home lab, served at
the apex domain. Built with Next.js (App Router) + Tailwind. Part of the
[farallon-infra](../) repo; see [OPERATIONS.md](../OPERATIONS.md) for how it is
deployed onto the acquisition VM.

## Routes

- `/` — personal landing page.
- `/directory` — every self-hosted app with a plain-English description, a link,
  and a live online/offline badge, plus a **System Health** strip (VPN exit
  IP/country, Mullvad days-to-expiry, storage usage, last-backup age, *arr
  health).
- `/api/status` — server-side health collector. API keys live only on the
  server (`src/lib/status.ts`); the browser only ever receives booleans + safe
  display strings.

## Local development

```bash
cp .env.example .env.local   # then fill in service URLs / keys as needed
npm install
npm run dev                  # http://localhost:3000
```

`npm run build` produces a standalone server bundle; `npm run lint` runs ESLint.

## Configuration

All runtime config is environment-driven — see [.env.example](.env.example).
In production these values are injected by Terraform into `dashboard.env`
(see `scripts/deploy-dashboard.sh`), which pulls the live *arr API keys and the
gluetun control-server key off the VM. Every value falls back to a sensible LAN
default so the app runs locally with no setup.
