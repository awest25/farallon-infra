#!/bin/bash
# ==============================================================================
# NPM First-Time Setup + Proxy Host Configuration
# ==============================================================================
# This script is rendered by Terraform's templatefile() and executed inside
# the reverse-proxy LXC (101). It:
#   1. Resets NPM to a clean state (drops volume, restarts)
#   2. Creates the admin user via the API (NPM v2.14+)
#   3. Sets the admin password via direct DB insertion (bcrypt hash)
#   4. Creates all proxy hosts from Terraform config
#
# This is fully idempotent — Terraform is the source of truth for proxy hosts.
set -euo pipefail

NPM_URL="http://localhost:81"

# --- Wait for NPM API --------------------------------------------------------
echo "Waiting for NPM to be ready..."
for i in $(seq 1 60); do
  if curl -sf "$NPM_URL/api/" >/dev/null 2>&1; then
    echo "NPM is ready!"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: NPM did not become ready in time"
    exit 1
  fi
  sleep 2
done

# --- Reset to factory (idempotent — Terraform owns proxy host state) ----------
echo "Resetting NPM to clean state..."
cd /opt/reverse-proxy
docker compose down
docker volume rm reverse-proxy_npm_data reverse-proxy_npm_letsencrypt 2>/dev/null || true
docker compose up -d
sleep 20

# Wait until API responds
for i in $(seq 1 60); do
  if curl -sf "$NPM_URL/api/" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

# --- Create initial admin user (NPM v2.14+ setup flow) -----------------------
echo "Creating admin user..."
curl -sf "$NPM_URL/api/users" -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"Admin","email":"${admin_email}","nickname":"Admin"}' > /dev/null

# --- Set password via DB (NPM v2.14+ doesn't accept 'secret' in user create) --
echo "Setting admin password..."
DBPATH=$(docker inspect npm --format='{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}')
HASH=$(docker exec npm node -e "
const bcrypt = require('bcrypt');
const hash = bcrypt.hashSync('${admin_password}', 13);
process.stdout.write(hash);
")
sqlite3 "$DBPATH/database.sqlite" \
  "INSERT INTO auth (user_id, type, secret, meta, created_on, modified_on) VALUES (1, 'password', '$HASH', '{}', datetime('now'), datetime('now'));"

# --- Login with configured credentials ----------------------------------------
echo "Logging in..."
TOKEN=$(curl -sf "$NPM_URL/api/tokens" -X POST \
  -H "Content-Type: application/json" \
  -d '{"identity":"${admin_email}","secret":"${admin_password}"}' | jq -r '.token // empty')

if [ -z "$TOKEN" ]; then
  echo "ERROR: Login failed"
  exit 1
fi

# --- Create proxy hosts -------------------------------------------------------
create_proxy() {
  local fqdn="$1"
  local host="$2"
  local port="$3"

  echo "  $fqdn → $host:$port"
  curl -sf "$NPM_URL/api/nginx/proxy-hosts" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"domain_names\": [\"$fqdn\"],
      \"forward_scheme\": \"http\",
      \"forward_host\": \"$host\",
      \"forward_port\": $port,
      \"access_list_id\": 0,
      \"certificate_id\": 0,
      \"meta\": {\"letsencrypt_agree\": false, \"dns_challenge\": false},
      \"advanced_config\": \"\",
      \"locations\": [],
      \"block_exploits\": true,
      \"caching_enabled\": false,
      \"allow_websocket_upgrade\": true,
      \"http2_support\": false,
      \"hsts_enabled\": false,
      \"hsts_subdomains\": false,
      \"ssl_forced\": false
    }" >/dev/null
}

echo "Creating proxy hosts..."
create_proxy "jellyfin.${domain}"  "${jellyfin_ip}"     8096
create_proxy "requests.${domain}"  "${acquisition_ip}"  5055
create_proxy "sonarr.${domain}"    "${acquisition_ip}"  8989
create_proxy "radarr.${domain}"    "${acquisition_ip}"  7878
create_proxy "prowlarr.${domain}"  "${acquisition_ip}"  9696
create_proxy "qbit.${domain}"      "${acquisition_ip}"  8080

echo ""
echo "=== NPM Setup Complete ==="
echo "Admin: ${admin_email}"
echo "Proxy hosts created: 6"
