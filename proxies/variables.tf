variable "proxmox_api_url" {
  description = "The URL of the Proxmox API (e.g. https://192.168.1.100:8006/)"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "The Proxmox API Token ID (e.g. root@pam!opentofu)"
  type        = string
}

variable "proxmox_api_token_secret" {
  description = "The Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "target_node" {
  description = "The Proxmox node to deploy resources on"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH Public Key for the VM user"
  type        = string
}

variable "ci_user" {
  description = "User to create in the VM"
  type        = string
  default     = "ubuntu"
}

variable "wireguard_server_url" {
  description = "Public IP or DNS name for the Wireguard endpoint (clients connect to this)"
  type        = string
}

variable "wireguard_server_port" {
  description = "UDP port for Wireguard"
  type        = number
  default     = 51820
}

variable "wireguard_peers" {
  description = "Number of Wireguard peer configs to generate"
  type        = number
  default     = 1
}
