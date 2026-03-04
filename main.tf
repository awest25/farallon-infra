terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.73.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = true

  ssh {
    agent    = true
    username = "root"

    node {
      name    = var.target_node
      address = "127.0.0.1"
      port    = 10022
    }
  }
}

# --- LXC Container Template ---------------------------------------------------
# Auto-detects and downloads the latest Debian 12 CT template using pveam.
# No hardcoded URLs or version numbers — pveam always knows what's available.
data "external" "lxc_template" {
  program = [
    "ssh", "-o", "StrictHostKeyChecking=no",
    "root@${var.proxmox_host_ip}",
    "bash", "-c",
    "pveam update >/dev/null 2>&1; T=$(pveam available --section system | grep 'debian-12-standard' | awk '{print $2}' | sort -V | tail -1); pveam download local $T >/dev/null 2>&1 || true; echo \"{\\\"template\\\": \\\"$T\\\"}\""
  ]
}

locals {
  lxc_template_id = "local:vztmpl/${data.external.lxc_template.result.template}"
  public_hostname = "${var.duckdns_domain}.duckdns.org"
}

# --- DuckDNS Auto-Update on Proxmox Host -------------------------------------
# Keeps the DuckDNS record pointed at the current public IP so the infra
# survives ISP IP changes without manual intervention.
resource "null_resource" "duckdns_setup" {
  connection {
    type         = "ssh"
    host         = var.proxmox_host_ip
    user         = "root"
    agent        = true
    bastion_host = local.public_hostname
    bastion_port = 52222
    bastion_user = "root"
  }

  provisioner "remote-exec" {
    inline = [
      # Create the update script
      "cat > /usr/local/bin/duckdns-update.sh << 'SCRIPT'\n#!/bin/bash\ncurl -s \"https://www.duckdns.org/update?domains=${var.duckdns_domain}&token=${var.duckdns_token}&ip=\" -o /tmp/duckdns-update.log\nSCRIPT",
      "chmod +x /usr/local/bin/duckdns-update.sh",

      # Run immediately to ensure the record is current
      "/usr/local/bin/duckdns-update.sh",

      # Install cron job (every 5 minutes)
      "echo '*/5 * * * * root /usr/local/bin/duckdns-update.sh' > /etc/cron.d/duckdns",
    ]
  }
}

# --- NFS Server on Proxmox Host -----------------------------------------------
# Exports the shared storage directory so the acquisition VM can mount it.
# The Jellyfin LXC uses a direct bind mount; this NFS export is for VMs only.
resource "null_resource" "nfs_server_setup" {
  connection {
    type         = "ssh"
    host         = var.proxmox_host_ip
    user         = "root"
    agent        = true
    bastion_host = local.public_hostname
    bastion_port = 52222
    bastion_user = "root"
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get install -y nfs-kernel-server",
      "mkdir -p ${var.storage_host_path}",
      "grep -q '${var.storage_host_path}.*10.0.0.0/24' /etc/exports || echo '${var.storage_host_path} 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)' >> /etc/exports",
      "exportfs -ra",
      "systemctl enable --now nfs-kernel-server",

      # Create shared directories with correct ownership
      # Owner 100103 = Jellyfin user inside unprivileged LXC (UID 103 + 100000 offset)
      # Group 1000 = container PUID (Sonarr/Radarr/qBit)
      # 775 = both Jellyfin (owner) and arr stack (group) can read/write
      "mkdir -p ${var.storage_host_path}/{media/movies,media/shows,torrents/automated,torrents/manual,backups}",
      "chown -R 100103:1000 ${var.storage_host_path}/media ${var.storage_host_path}/torrents",
      "chmod -R 775 ${var.storage_host_path}/media ${var.storage_host_path}/torrents",
    ]
  }
}
