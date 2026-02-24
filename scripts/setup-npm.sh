#!/bin/bash
# ==============================================================================
# NPM Proxy Host + SSL Configuration
# ==============================================================================
# This script is rendered by Terraform's templatefile() and executed inside
# the reverse-proxy LXC (101). It:
#   1. Logs into NPM (admin user is created via INITIAL_ADMIN_* env vars)
#   2. Ensures all proxy hosts exist (skips existing ones)
#   3. Requests Let's Encrypt certificates for each host
#
# Safe to re-run — skips existing proxy hosts and certs.
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

# --- Authenticate -------------------------------------------------------------
TOKEN=$(curl -sf "$NPM_URL/api/tokens" -X POST \
  -H "Content-Type: application/json" \
  -d '{"identity":"${admin_email}","secret":"${admin_password}"}' | jq -r '.token // empty' 2>/dev/null || true)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Login failed. Check INITIAL_ADMIN_EMAIL/PASSWORD env vars on the npm container."
  exit 1
fi
echo "Logged in as ${admin_email}"

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
      \"meta\": {},
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

# --- Request Let's Encrypt certs (skip if already assigned) --------------------
echo "Ensuring SSL certificates..."
HOSTS=$(curl -sf "$NPM_URL/api/nginx/proxy-hosts" -H "Authorization: Bearer $TOKEN")

echo "$HOSTS" | jq -c '.[]' | while read -r HOST; do
  ID=$(echo "$HOST" | jq -r '.id')
  DOMAIN=$(echo "$HOST" | jq -r '.domain_names[0]')
  CERT_ID=$(echo "$HOST" | jq -r '.certificate_id')

  if [ "$CERT_ID" != "0" ] && [ "$CERT_ID" != "null" ]; then
    echo "  $DOMAIN: cert exists (id=$CERT_ID), skipping"
    continue
  fi

  echo "  $DOMAIN: requesting Let's Encrypt certificate..."
  CERT=$(curl -s "$NPM_URL/api/nginx/certificates" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"domain_names\": $(echo "$HOST" | jq '.domain_names'),
      \"meta\": { \"dns_challenge\": false },
      \"provider\": \"letsencrypt\"
    }")

  NEW_CERT_ID=$(echo "$CERT" | jq -r '.id // empty')
  if [ -z "$NEW_CERT_ID" ]; then
    echo "    WARNING: cert request failed: $(echo "$CERT" | jq -r '.error.message // "unknown"')"
    continue
  fi

  # Apply cert to proxy host with SSL forced + HSTS + HTTP/2
  curl -sf "$NPM_URL/api/nginx/proxy-hosts/$ID" \
    -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(echo "$HOST" | jq --argjson cid "$NEW_CERT_ID" '{
      domain_names: .domain_names,
      forward_scheme: .forward_scheme,
      forward_host: .forward_host,
      forward_port: .forward_port,
      access_list_id: .access_list_id,
      certificate_id: $cid,
      meta: .meta,
      advanced_config: .advanced_config,
      locations: .locations,
      block_exploits: .block_exploits,
      caching_enabled: .caching_enabled,
      allow_websocket_upgrade: .allow_websocket_upgrade,
      http2_support: true,
      hsts_enabled: true,
      hsts_subdomains: false,
      ssl_forced: true
    }')" > /dev/null

  echo "    $DOMAIN: HTTPS enabled"
done

echo ""
echo "=== NPM Setup Complete ==="
echo "Admin: ${admin_email}"
