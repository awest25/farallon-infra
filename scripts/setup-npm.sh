#!/bin/bash
# ==============================================================================
# NPM First-Time Setup + Proxy Host Configuration
# ==============================================================================
# This script is rendered by Terraform's templatefile() and executed inside
# the reverse-proxy LXC (101). It:
#   1. Checks if NPM is already configured (non-destructive)
#   2. Creates the admin user if this is a fresh install
#   3. Ensures all proxy hosts exist (skips existing ones)
#
# Safe to re-run — will not reset an already-configured NPM instance.
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

# --- Authenticate (or set up fresh install) -----------------------------------
TOKEN=$(curl -sf "$NPM_URL/api/tokens" -X POST \
  -H "Content-Type: application/json" \
  -d '{"identity":"${admin_email}","secret":"${admin_password}"}' 2>/dev/null | jq -r '.token // empty' 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "First-time setup: creating admin user..."

  # Create admin user (NPM v2.14+ setup flow)
  curl -sf "$NPM_URL/api/users" -X POST \
    -H "Content-Type: application/json" \
    -d '{"name":"Admin","email":"${admin_email}","nickname":"Admin"}' > /dev/null

  # Set password via DB (NPM v2.14+ doesn't accept 'secret' in user create)
  DBPATH=$(docker inspect npm --format='{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}')
  HASH=$(docker exec npm node -e "
const bcrypt = require('bcrypt');
const hash = bcrypt.hashSync('${admin_password}', 13);
process.stdout.write(hash);
")
  sqlite3 "$DBPATH/database.sqlite" \
    "INSERT INTO auth (user_id, type, secret, meta, created_on, modified_on) VALUES (1, 'password', '$HASH', '{}', datetime('now'), datetime('now'));"

  # Login with the new credentials
  TOKEN=$(curl -sf "$NPM_URL/api/tokens" -X POST \
    -H "Content-Type: application/json" \
    -d '{"identity":"${admin_email}","secret":"${admin_password}"}' | jq -r '.token // empty')

  if [ -z "$TOKEN" ]; then
    echo "ERROR: Login failed after user creation"
    exit 1
  fi
  echo "Admin user created successfully."
else
  echo "NPM already configured, skipping user setup."
fi

# --- Create proxy hosts (skip existing) ---------------------------------------
EXISTING=$(curl -sf "$NPM_URL/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.[].domain_names[0]' 2>/dev/null || true)

create_proxy() {
  local fqdn="$1"
  local host="$2"
  local port="$3"

  if echo "$EXISTING" | grep -qx "$fqdn"; then
    echo "  $fqdn (exists, skipping)"
    return
  fi

  echo "  $fqdn -> $host:$port"
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

echo "Ensuring proxy hosts exist..."
create_proxy "jellyfin.${domain}"  "${jellyfin_ip}"     8096
create_proxy "requests.${domain}"  "${acquisition_ip}"  5055
create_proxy "sonarr.${domain}"    "${acquisition_ip}"  8989
create_proxy "radarr.${domain}"    "${acquisition_ip}"  7878
create_proxy "prowlarr.${domain}"  "${acquisition_ip}"  9696
create_proxy "qbit.${domain}"      "${acquisition_ip}"  8080

echo ""
echo "=== NPM Setup Complete ==="
echo "Admin: ${admin_email}"
