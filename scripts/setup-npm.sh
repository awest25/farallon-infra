#!/bin/bash
# ==============================================================================
# NPM Proxy Host + SSL Configuration
# ==============================================================================
# This script is rendered by Terraform's templatefile() and executed inside
# the reverse-proxy LXC (101). It:
#   1. Logs into NPM (admin user is created via INITIAL_ADMIN_* env vars)
#   2. Creates/updates the internal-only access list (LAN + WireGuard)
#   3. Ensures all proxy hosts exist, converging their access rules in place
#   4. Requests Let's Encrypt certificates for hosts that don't have one
#
# Safe to re-run — proxy hosts converge in place and existing certs are
# preserved (only missing certs are requested).
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

# --- Internal-only access list (LAN + WireGuard) ------------------------------
# Single source of truth for who may reach the locked-down admin panels: the LAN
# and the WireGuard peer subnet. Everyone else (real public source IPs, preserved
# through the router's DNAT) is denied.
#
# DECISION: gate the *arr/qbit panels with a real NPM Access List (set via
# access_list_id) rather than a raw "deny all;" in advanced_config. NPM injects
# the access list *inside* the proxied "location /" only, so the Let's Encrypt
# /.well-known/acme-challenge path stays reachable and cert renewal keeps working
# — a server-level "deny all;" would silently break renewal. The dashboard's
# per-path gating still uses custom locations, since access lists are whole-host
# only.
# The two allowed CIDRs are the access boundary; define them once so the JSON
# access list and the nginx snippet below can never drift apart.
LAN_SUBNET="10.0.0.0/24"      # home LAN
WG_SUBNET="10.13.13.0/24"     # WireGuard peers

ACL_NAME="internal-only (LAN + WireGuard)"
ACL_BODY=$(jq -n --arg name "$ACL_NAME" --arg lan "$LAN_SUBNET" --arg wg "$WG_SUBNET" '{
  name: $name,
  satisfy_any: true,
  pass_auth: false,
  items: [],
  clients: [
    { address: $lan, directive: "allow" },
    { address: $wg,  directive: "allow" }
  ]
}')

ACL_ID=$(curl -sf "$NPM_URL/api/nginx/access-lists" -H "Authorization: Bearer $TOKEN" \
  | jq -r --arg n "$ACL_NAME" 'map(select(.name == $n)) | .[0].id // empty')

if [ -z "$ACL_ID" ]; then
  echo "Creating access list: $ACL_NAME"
  ACL_ID=$(echo "$ACL_BODY" | curl -sf "$NPM_URL/api/nginx/access-lists" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d @- | jq -r '.id // empty')
else
  echo "Updating access list: $ACL_NAME (id=$ACL_ID)"
  echo "$ACL_BODY" | curl -sf "$NPM_URL/api/nginx/access-lists/$ACL_ID" -X PUT \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d @- >/dev/null
fi

if [ -z "$ACL_ID" ]; then
  echo "ERROR: could not create or find access list '$ACL_NAME'"
  exit 1
fi

# nginx allow/deny snippet for per-location gating on the public apex/www hosts.
# Mirrors the access list above (whose final "deny all;" NPM adds automatically).
INTERNAL_ACL=$(printf 'allow %s;\nallow %s;\ndeny all;' "$LAN_SUBNET" "$WG_SUBNET")

# Gate only the dashboard's data endpoints; the homepage (location /) stays public.
# Both custom locations proxy to the same Next.js app on the acquisition VM.
DASHBOARD_LOCATIONS=$(jq -n --arg host "${acquisition_ip}" --arg acl "$INTERNAL_ACL" '[
  { path: "/directory",  forward_scheme: "http", forward_host: $host, forward_port: 3000, advanced_config: $acl },
  { path: "/api/status", forward_scheme: "http", forward_host: $host, forward_port: 3000, advanced_config: $acl }
]')

# --- Upsert proxy hosts (create if missing, otherwise converge in place) -------
# DECISION: always write the desired config onto existing hosts instead of
# skip-if-exists, so re-runs apply the gating to hosts that already exist on the
# live system. Existing certificate + SSL fields are read back and preserved, so
# we never drop a cert or trigger a needless Let's Encrypt re-issue.
ALL_HOSTS=$(curl -sf "$NPM_URL/api/nginx/proxy-hosts" -H "Authorization: Bearer $TOKEN")

upsert_proxy() {
  local fqdn="$1" host="$2" port="$3" adv="$4" locations="$5" acl="$6"
  local existing
  existing=$(echo "$ALL_HOSTS" | jq -c --arg d "$fqdn" 'map(select(.domain_names[0] == $d)) | .[0] // empty')

  if [ -n "$existing" ]; then
    local id
    id=$(echo "$existing" | jq -r '.id')
    echo "  $fqdn (updating id=$id)"
    echo "$existing" | jq \
      --arg host "$host" --argjson port "$port" --arg adv "$adv" \
      --argjson locations "$locations" --argjson acl "$acl" \
      '{
        domain_names,
        forward_scheme,
        forward_host: $host,
        forward_port: $port,
        access_list_id: $acl,
        certificate_id,
        ssl_forced, hsts_enabled, hsts_subdomains, http2_support,
        meta,
        advanced_config: $adv,
        locations: $locations,
        block_exploits, caching_enabled, allow_websocket_upgrade
      }' | curl -sf "$NPM_URL/api/nginx/proxy-hosts/$id" -X PUT \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
        -d @- >/dev/null
  else
    echo "  $fqdn -> $host:$port (creating)"
    jq -n \
      --arg fqdn "$fqdn" --arg host "$host" --argjson port "$port" --arg adv "$adv" \
      --argjson locations "$locations" --argjson acl "$acl" \
      '{
        domain_names: [$fqdn],
        forward_scheme: "http",
        forward_host: $host,
        forward_port: $port,
        access_list_id: $acl,
        certificate_id: 0,
        ssl_forced: false, hsts_enabled: false, hsts_subdomains: false, http2_support: false,
        meta: {},
        advanced_config: $adv,
        locations: $locations,
        block_exploits: true, caching_enabled: false, allow_websocket_upgrade: true
      }' | curl -sf "$NPM_URL/api/nginx/proxy-hosts" \
        -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
        -d @- >/dev/null
  fi
}

echo "Ensuring proxy hosts exist (and converging access rules)..."
# Public — personal site, blog, and media (each has its own login where relevant).
# Apex + www gate only /directory + /api/status; the homepage stays open.
upsert_proxy "${domain}"           "${acquisition_ip}"  3000 "" "$DASHBOARD_LOCATIONS" 0
upsert_proxy "www.${domain}"       "${acquisition_ip}"  3000 "" "$DASHBOARD_LOCATIONS" 0
upsert_proxy "blog.${domain}"      "${acquisition_ip}"  3001 "" "[]" 0
upsert_proxy "jellyfin.${domain}"  "${jellyfin_ip}"     8096 "" "[]" 0
upsert_proxy "requests.${domain}"  "${acquisition_ip}"  5055 "" "[]" 0
# Internal-only — *arr admin panels + torrent client, gated host-wide to LAN/VPN.
upsert_proxy "sonarr.${domain}"    "${acquisition_ip}"  8989 "" "[]" "$ACL_ID"
upsert_proxy "radarr.${domain}"    "${acquisition_ip}"  7878 "" "[]" "$ACL_ID"
upsert_proxy "prowlarr.${domain}"  "${acquisition_ip}"  9696 "" "[]" "$ACL_ID"
upsert_proxy "qbit.${domain}"      "${acquisition_ip}"  8080 "" "[]" "$ACL_ID"

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
