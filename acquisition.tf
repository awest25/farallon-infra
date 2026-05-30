# ==============================================================================
# Acquisition Stack — Docker VM
# ==============================================================================
# Full VM (not LXC) because Gluetun needs kernel-level WireGuard + /dev/net/tun.
# Houses the entire automated media pipeline + ad-hoc torrent downloads.
#
# Services:
#   - Gluetun      (VPN gateway — Mullvad WireGuard)
#   - qBittorrent  (downloader — bound to Gluetun network namespace)
#   - Prowlarr     (indexer sync)
#   - Sonarr       (TV manager)
#   - Radarr       (movie manager)
#   - Jellyseerr   (request portal for friends)
#   - FlareSolverr (Cloudflare bypass proxy for Prowlarr)
#
# Storage layout inside the VM:
#   /mnt/storage/media/movies/       ← Radarr hardlinks finished movies
#   /mnt/storage/media/shows/        ← Sonarr hardlinks finished shows
#   /mnt/storage/torrents/automated/ ← Sonarr/Radarr download target
#   /mnt/storage/torrents/manual/    ← Ad-hoc Mac downloads via qBit WebUI

resource "proxmox_virtual_environment_file" "acquisition_cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_file {
    path = "${path.module}/cloud-init/acquisition.yml"
  }
}

resource "proxmox_virtual_environment_vm" "acquisition" {
  name      = "acquisition"
  node_name = var.target_node
  vm_id     = 103

  clone {
    vm_id = 9000
    full  = true
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  # The *arr stack is memory-hungry — 4GB minimum recommended
  memory {
    dedicated = 4096
  }

  # OS disk
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    ssd          = true
    discard      = "on"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${var.acquisition_ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.acquisition_cloud_init.id
  }

  network_device {
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [disk]
  }
}

# --- Post-provision: inject Mullvad creds, mount NFS, start stack -------------
# Cloud-init writes the docker-compose.yml but can't template Terraform vars.
# This provisioner creates the .env file Docker Compose needs, mounts NFS from
# the Proxmox host, and (re)starts the full stack.
resource "null_resource" "acquisition_setup" {
  depends_on = [
    proxmox_virtual_environment_vm.acquisition,
    null_resource.nfs_server_setup,
  ]

  triggers = {
    vm_id       = proxmox_virtual_environment_vm.acquisition.vm_id
    mullvad_key = var.mullvad_wireguard_private_key
  }

  connection {
    type         = "ssh"
    host         = var.acquisition_ip
    user         = "ubuntu"
    agent        = true
    bastion_host = local.public_hostname
    bastion_port = 52222
    bastion_user = "root"
  }

  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to finish (first boot only)
      "cloud-init status --wait 2>/dev/null || true",

      # --- Create .env for Docker Compose (Mullvad VPN credentials) ---------------
      "printf 'MULLVAD_WIREGUARD_PRIVATE_KEY=%s\\nMULLVAD_WIREGUARD_ADDRESSES=%s\\n' '${var.mullvad_wireguard_private_key}' '${var.mullvad_wireguard_addresses}' | sudo tee /opt/acquisition/.env > /dev/null",

      # --- Mount NFS from Proxmox host --------------------------------------------
      "sudo mkdir -p /mnt/storage",
      "grep -q '${var.proxmox_host_ip}:${var.storage_host_path}' /etc/fstab || echo '${var.proxmox_host_ip}:${var.storage_host_path} /mnt/storage nfs defaults,_netdev 0 0' | sudo tee -a /etc/fstab > /dev/null",
      "sudo mount -a",

      # Create directory structure if not already present
      "sudo mkdir -p /mnt/storage/media/movies /mnt/storage/media/shows /mnt/storage/torrents/automated /mnt/storage/torrents/manual",

      # --- Restore config from backup if available ---------------------------------
      "sudo mkdir -p /opt/acquisition/appdata",
      "sudo mkdir -p /mnt/storage/backups",
      "LATEST=$(ls -t /mnt/storage/backups/acquisition-*.tar.gz 2>/dev/null | head -1); if [ -n \"$LATEST\" ]; then echo \"Restoring from: $LATEST\"; sudo tar xzf \"$LATEST\" -C /opt/acquisition/appdata/; fi",

      # --- (Re)start the Docker stack ---------------------------------------------
      "cd /opt/acquisition && sudo docker compose down 2>/dev/null || true",
      "cd /opt/acquisition && sudo docker compose up -d",
    ]
  }
}

# --- Personal dashboard: landing page + live directory/status ----------------
# Next.js app shipped as source and built on the VM (amd64). Reads service
# health over the LAN and VPN status from gluetun's control API. Rebuilds
# automatically whenever the dashboard source or deploy script changes.
resource "null_resource" "dashboard_deploy" {
  depends_on = [null_resource.acquisition_setup]

  triggers = {
    src_hash = sha1(join(",", [
      for f in fileset("${path.module}/dashboard", "{src/**,public/**,package.json,package-lock.json,Dockerfile,docker-compose.yml,next.config.ts,tsconfig.json,components.json,postcss.config.mjs,eslint.config.mjs,.dockerignore}") :
      filesha1("${path.module}/dashboard/${f}")
    ]))
    deploy_script   = filesha1("${path.module}/scripts/deploy-dashboard.sh")
    mullvad_account = var.mullvad_account_number
  }

  connection {
    type         = "ssh"
    host         = var.acquisition_ip
    user         = "ubuntu"
    agent        = true
    bastion_host = local.public_hostname
    bastion_port = 52222
    bastion_user = "root"
  }

  # Tar the source (excluding heavy/secret files) and ship it.
  provisioner "local-exec" {
    command = "cd ${path.module}/dashboard && COPYFILE_DISABLE=1 tar czf /tmp/farallon-dashboard.tgz --exclude=./node_modules --exclude=./.next --exclude=./.env.local --exclude=./.git --exclude=./dashboard.env ."
  }
  provisioner "file" {
    source      = "/tmp/farallon-dashboard.tgz"
    destination = "/tmp/farallon-dashboard.tgz"
  }

  # Render the deploy script with Terraform values.
  provisioner "file" {
    content = templatefile("${path.module}/scripts/deploy-dashboard.sh", {
      domain                 = var.domain
      jellyfin_ip            = var.jellyfin_ip
      acquisition_ip         = var.acquisition_ip
      mullvad_account_number = var.mullvad_account_number
    })
    destination = "/tmp/deploy-dashboard.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/acquisition/dashboard",
      "sudo tar xzf /tmp/farallon-dashboard.tgz -C /opt/acquisition/dashboard",
      "sudo chown -R ubuntu:ubuntu /opt/acquisition/dashboard",
      "bash /tmp/deploy-dashboard.sh",
      "rm -f /tmp/deploy-dashboard.sh /tmp/farallon-dashboard.tgz",
    ]
  }
}
