# ==============================================================================
# Proxmox Connection
# ==============================================================================
variable "proxmox_api_url" {
  description = "Proxmox API endpoint (e.g. https://10.0.0.32:8006/)"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID (e.g. root@pam!opentofu)"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "Proxmox node name to deploy all resources on"
  type        = string
}

variable "proxmox_host_ip" {
  description = "IP address of the Proxmox host (for SSH provisioners)"
  type        = string
}

# ==============================================================================
# SSH
# ==============================================================================
variable "ssh_public_keys" {
  description = "SSH public keys for VM/LXC access"
  type        = list(string)
}

# ==============================================================================
# Network
# ==============================================================================
variable "network_gateway" {
  description = "Default gateway for the LAN"
  type        = string
  default     = "10.0.0.1"
}

variable "network_cidr" {
  description = "CIDR suffix for static IPs"
  type        = string
  default     = "24"
}

variable "wireguard_ip" {
  description = "Static IP for the WireGuard server VM"
  type        = string
  default     = "10.0.0.116"
}

variable "jellyfin_ip" {
  description = "Static IP for the Jellyfin LXC"
  type        = string
  default     = "10.0.0.33"
}

variable "acquisition_ip" {
  description = "Static IP for the acquisition (Docker) VM"
  type        = string
  default     = "10.0.0.34"
}

variable "reverse_proxy_ip" {
  description = "Static IP for the reverse proxy LXC"
  type        = string
  default     = "10.0.0.136"
}

# ==============================================================================
# Storage
# ==============================================================================
variable "storage_host_path" {
  description = "Path on the Proxmox host to the shared storage array (bind-mounted into LXCs, NFS-mounted into VMs)"
  type        = string
  default     = "/mnt/storage"
}

# ==============================================================================
# Mullvad VPN (for Gluetun in the acquisition stack)
# ==============================================================================
variable "mullvad_wireguard_private_key" {
  description = "Mullvad WireGuard private key for Gluetun"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mullvad_wireguard_addresses" {
  description = "Mullvad WireGuard addresses for Gluetun (e.g. 10.x.x.x/32)"
  type        = string
  default     = ""
}

# ==============================================================================
# Domain & Reverse Proxy
# ==============================================================================
variable "domain" {
  description = "Base domain for subdomains (e.g., alexanderwest.com)"
  type        = string
  default     = "alexanderwest.com"
}

variable "npm_admin_password" {
  description = "Password for the Nginx Proxy Manager admin panel"
  type        = string
  sensitive   = true
}

# ==============================================================================
# DuckDNS (dynamic DNS)
# ==============================================================================
variable "duckdns_token" {
  description = "DuckDNS API token for dynamic DNS updates"
  type        = string
  sensitive   = true
}

variable "duckdns_domain" {
  description = "DuckDNS subdomain (without .duckdns.org suffix)"
  type        = string
  default     = "farallon-sf"
}
