#!/bin/bash
# ==============================================================================
# Dashboard deploy (rendered by Terraform templatefile, run on acquisition VM)
# ==============================================================================
# Configures gluetun's control-server auth, writes the dashboard runtime env
# (with the live *arr API keys), and (re)builds the dashboard container.
# Safe to re-run — the gluetun API key is generated once and reused.
set -uo pipefail

# --- gluetun control-server API key (generate once, persist) -----------------
AUTH_DIR=/opt/acquisition/appdata/gluetun/auth
AUTH=$AUTH_DIR/config.toml
sudo mkdir -p "$AUTH_DIR"
NEW_KEY=0
KEY=""
if sudo test -f "$AUTH"; then KEY=$(sudo grep -oP 'apikey = "\K[^"]+' "$AUTH" | head -1); fi
if [ -z "$KEY" ]; then
  KEY=$(sudo docker run --rm qmcgaw/gluetun genkey 2>/dev/null | tr -d '\r\n')
  [ -z "$KEY" ] && KEY=$(openssl rand -hex 16)
  printf '[[roles]]\nname = "dashboard"\nroutes = ["GET /v1/publicip/ip"]\nauth = "apikey"\napikey = "%s"\n' "$KEY" | sudo tee "$AUTH" >/dev/null
  sudo chown -R 1000:1000 "$AUTH_DIR"
  NEW_KEY=1
fi

# --- dashboard.env (live *arr API keys from restored appdata) -----------------
SK=$(sudo grep -oP '(?<=<ApiKey>)[^<]+' /opt/acquisition/appdata/sonarr/config.xml 2>/dev/null || true)
RK=$(sudo grep -oP '(?<=<ApiKey>)[^<]+' /opt/acquisition/appdata/radarr/config.xml 2>/dev/null || true)
PK=$(sudo grep -oP '(?<=<ApiKey>)[^<]+' /opt/acquisition/appdata/prowlarr/config.xml 2>/dev/null || true)
sudo tee /opt/acquisition/dashboard/dashboard.env >/dev/null <<EOF
NEXT_PUBLIC_DOMAIN=${domain}
JELLYFIN_URL=http://${jellyfin_ip}:8096
JELLYSEERR_URL=http://${acquisition_ip}:5055
SONARR_URL=http://${acquisition_ip}:8989
RADARR_URL=http://${acquisition_ip}:7878
PROWLARR_URL=http://${acquisition_ip}:9696
QBIT_URL=http://${acquisition_ip}:8080
SONARR_API_KEY=$SK
RADARR_API_KEY=$RK
PROWLARR_API_KEY=$PK
GLUETUN_URL=http://${acquisition_ip}:8000
GLUETUN_API_KEY=$KEY
MULLVAD_ACCOUNT_NUMBER=${mullvad_account_number}
STORAGE_PATH=/mnt/storage
DISK_WARN_PCT=92
EOF

# If we just turned on the control server, restart gluetun (and qbittorrent,
# which shares its network namespace) so the API key takes effect.
if [ "$NEW_KEY" = "1" ]; then
  cd /opt/acquisition && sudo docker compose up -d gluetun && sudo docker restart qbittorrent || true
fi

# --- build + start the dashboard ---------------------------------------------
cd /opt/acquisition/dashboard && sudo docker compose up -d --build
echo "dashboard deploy complete"
