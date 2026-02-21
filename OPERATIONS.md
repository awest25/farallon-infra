# Farallon Home Lab — Operations Guide

## Data Persistence

### The Problem

The arr stack (Sonarr, Radarr, Prowlarr, Overseerr, qBittorrent) stores all
configuration in SQLite databases. A `tofu destroy` wipes the VM disk, losing
every indexer, download client, quality profile, and connection you configured.

Media files on `/mnt/storage` survive (they live on the Proxmox host via NFS),
but the app config does not.

### The Solution: Cattle VMs, Persistent Storage

Everything is cattle. All VMs and LXCs can be destroyed and recreated freely.
The only stateful thing is `/mnt/storage` on the Proxmox host, which Terraform
does not manage.

**Bind mounts instead of Docker named volumes**

App config lives at `/opt/acquisition/appdata/<service>/` on the VM's local disk
(not Docker named volumes). This means `docker compose down -v` won't wipe config.
SQLite databases stay on local disk (NFS is unsafe for SQLite due to broken file
locking and WAL mode incompatibility).

**Daily backup to NFS**

A cron job at 3:00 AM tars all appdata to `/mnt/storage/backups/` on the NFS
share. Keeps 7 days of backups. On VM recreation, the Terraform provisioner
restores from the latest backup before starting containers.

Backup script: `/opt/acquisition/backup.sh`
Cron definition: `/etc/cron.d/acquisition-backup`
Backup location: `/mnt/storage/backups/acquisition-*.tar.gz`

### What Survives What

| Scenario                       | Media | App Config | SSL Certs |
|--------------------------------|-------|------------|-----------|
| `docker compose down`          | Yes   | Yes        | Yes       |
| `docker compose down -v`       | Yes   | Yes        | Yes       |
| VM recreated (tofu destroy)    | Yes   | Restored from backup | Re-provision via Let's Encrypt |
| Proxmox host disk failure      | No    | No         | No        |

### Manual Backup (Before Intentional Destroy)

```bash
ssh ubuntu@10.0.0.34 'sudo /opt/acquisition/backup.sh'
```

---

## Deploying From Scratch

All VMs and LXCs are cattle — `tofu destroy` + `tofu apply` rebuilds everything.
App config is restored automatically from the latest NFS backup (if one exists).

```bash
tofu destroy
tofu apply
```

After apply, the system is running. If backups exist on NFS, app config is
restored automatically. If this is a fresh deploy with no backups, proceed to
"Initial Setup" below.

---

## Initial Setup (One-Time, Per Deploy)

These steps are manual but only needed once. After the first setup, backups
preserve all configuration across redeployments.

### 1. SSL Certificates

Log into NPM at `http://10.0.0.136:81`. Edit each proxy host and enable
Let's Encrypt (HTTP-01 challenge). Port 80 is already forwarded, so cert
issuance works immediately.

### 2. Change Default Passwords

- **NPM admin**: Change in the NPM UI (Users > Edit admin user)
- **qBittorrent**: Check container logs for the generated password:
  `ssh ubuntu@10.0.0.34 'docker logs qbittorrent 2>&1 | grep password'`
- **Sonarr/Radarr/Prowlarr**: Enable auth in each app's Settings > General

### 3. Wire Up the Arr Stack

1. **Prowlarr** (http://10.0.0.34:9696):
   - Add indexers (torrent trackers)
   - Add Sonarr and Radarr as "Apps" so indexers auto-sync

2. **Sonarr** (http://10.0.0.34:8989) and **Radarr** (http://10.0.0.34:7878):
   - Add qBittorrent as download client (host: `localhost`, port: `8080`)
   - Set root folders: `/data/media/shows` (Sonarr), `/data/media/movies` (Radarr)

3. **Overseerr** (http://10.0.0.34:5055):
   - Connect to Jellyfin (http://10.0.0.33:8096)
   - Connect to Sonarr and Radarr

### 4. Configure Recyclarr

Recyclarr auto-creates a default config on first start. Edit it with your
Sonarr/Radarr API keys and desired TRaSH Guide quality profiles:

```bash
ssh ubuntu@10.0.0.34
sudo vi /opt/acquisition/appdata/recyclarr/recyclarr.yml
```

Add your Sonarr/Radarr base URLs and API keys, then restart:

```bash
sudo docker restart recyclarr
```

Recyclarr syncs quality profiles daily by default.

---

## Directory Layout

### Acquisition VM (10.0.0.34)

```
/opt/acquisition/
  docker-compose.yml         # Stack definition (written by cloud-init)
  .env                       # Mullvad VPN credentials (written by provisioner)
  backup.sh                  # Daily backup script
  appdata/                   # All app config (bind-mounted into containers)
    gluetun/
    qbittorrent/
    prowlarr/
    sonarr/
    radarr/
    overseerr/
    recyclarr/

/mnt/storage/                # NFS mount from Proxmox host
  media/movies/              # Radarr output
  media/shows/               # Sonarr output
  torrents/automated/        # Arr stack downloads
  torrents/manual/           # Manual qBit downloads
  backups/                   # Daily config backups
```

### Reverse Proxy LXC (10.0.0.136)

```
/opt/reverse-proxy/
  docker-compose.yml
  data/
    npm/                     # NPM database, proxy host config
    letsencrypt/             # Let's Encrypt certificates
    crowdsec/config/         # CrowdSec configuration
    crowdsec/data/           # CrowdSec threat data
```

---

## Remaining TODO

- [ ] SSL certificates on all proxy hosts (NPM UI, one-time)
- [ ] Change NPM admin password
- [ ] Change qBittorrent default password
- [ ] Enable auth on Sonarr/Radarr/Prowlarr
- [ ] Wire up Prowlarr > Sonarr/Radarr > qBittorrent > Overseerr
- [ ] Configure Recyclarr with API keys and quality profiles
- [ ] Consider restricting Sonarr/Radarr/Prowlarr/qBit proxy hosts to VPN-only access
- [ ] CrowdSec bouncer (optional, after everything else is stable)
