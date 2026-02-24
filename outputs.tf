# ==============================================================================
# Outputs
# ==============================================================================

output "wireguard_ip" {
  description = "WireGuard VPN server IP"
  value       = var.wireguard_ip
}

output "reverse_proxy_ip" {
  description = "Reverse proxy LXC IP"
  value       = var.reverse_proxy_ip
}

output "jellyfin_ip" {
  description = "Jellyfin media server IP"
  value       = var.jellyfin_ip
}

output "acquisition_ip" {
  description = "Acquisition stack (Docker VM) IP"
  value       = var.acquisition_ip
}

output "service_urls" {
  description = "Direct LAN URLs for all services"
  value = {
    jellyfin    = "http://${var.jellyfin_ip}:8096"
    jellyseerr   = "http://${var.acquisition_ip}:5055"
    sonarr      = "http://${var.acquisition_ip}:8989"
    radarr      = "http://${var.acquisition_ip}:7878"
    prowlarr    = "http://${var.acquisition_ip}:9696"
    qbittorrent = "http://${var.acquisition_ip}:8080"
  }
}

output "proxy_hosts" {
  description = "NPM proxy host subdomains (configured automatically)"
  value = {
    jellyfin = "jellyfin.${var.domain}"
    requests = "requests.${var.domain}"
    sonarr   = "sonarr.${var.domain}"
    radarr   = "radarr.${var.domain}"
    prowlarr = "prowlarr.${var.domain}"
    qbit     = "qbit.${var.domain}"
  }
}

output "npm_admin" {
  description = "NPM admin panel access"
  value       = "Login: admin@${var.domain} at http://${var.reverse_proxy_ip}:81"
}
