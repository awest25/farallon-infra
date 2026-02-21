# ==============================================================================
# Outputs
# ==============================================================================

output "wireguard_ip" {
  description = "WireGuard VPN server IP"
  value       = var.wireguard_ip
}

output "reverse_proxy_id" {
  description = "Reverse proxy LXC container ID (check DHCP lease on your router for IP)"
  value       = proxmox_virtual_environment_container.reverse_proxy.vm_id
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
    overseerr   = "http://${var.acquisition_ip}:5055"
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
  value       = "Login: admin@${var.domain} (on the reverse proxy's DHCP IP, port 81)"
}
