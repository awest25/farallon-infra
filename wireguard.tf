# ==============================================================================
# WireGuard VPN Server
# ==============================================================================
# Personal WireGuard server for remote access into the home network.
# This is NOT the Mullvad VPN client (that's Gluetun in the acquisition stack).

resource "proxmox_virtual_environment_file" "wireguard_cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data = templatefile("${path.module}/cloud-init/wireguard.yml", {
      server_url = local.public_hostname
    })
    file_name = "wireguard.yml"
  }
}

resource "proxmox_virtual_environment_vm" "wireguard" {
  name      = "wireguard"
  node_name = var.target_node
  vm_id     = 100

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

  memory {
    dedicated = 2048
  }

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
        address = "${var.wireguard_ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.wireguard_cloud_init.id
  }

  network_device {
    bridge = "vmbr0"
  }

  lifecycle {
    ignore_changes = [disk]
  }
}

# --- Post-provision: mount NFS, restore config, set up backup ----------------
# Restores WireGuard keys from NFS backup so peer configs survive redeployment.
resource "null_resource" "wireguard_setup" {
  depends_on = [
    proxmox_virtual_environment_vm.wireguard,
    null_resource.nfs_server_setup,
  ]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.wireguard.vm_id
  }

  connection {
    type         = "ssh"
    host         = var.wireguard_ip
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

      # --- Mount NFS from Proxmox host --------------------------------------------
      "sudo mkdir -p /mnt/storage",
      "grep -q '${var.proxmox_host_ip}:${var.storage_host_path}' /etc/fstab || echo '${var.proxmox_host_ip}:${var.storage_host_path} /mnt/storage nfs defaults,_netdev 0 0' | sudo tee -a /etc/fstab > /dev/null",
      "sudo mount -a",
      "sudo mkdir -p /mnt/storage/backups",

      # --- Restore config from backup if available ---------------------------------
      "LATEST=$(ls -t /mnt/storage/backups/wireguard-*.tar.gz 2>/dev/null | head -1); if [ -n \"$LATEST\" ]; then echo \"Restoring WireGuard config from: $LATEST\"; sudo tar xzf \"$LATEST\" -C /opt/wireguard/config/; cd /opt/wireguard && sudo docker compose restart; fi",

      # --- Install daily backup cron ----------------------------------------------
      "echo '0 3 * * * root /opt/wireguard/backup.sh' | sudo tee /etc/cron.d/wireguard-backup > /dev/null",
    ]
  }
}
