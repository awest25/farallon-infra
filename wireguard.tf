# ==============================================================================
# WireGuard VPN Server
# ==============================================================================
# Personal WireGuard server for remote access into the home network.
# This is NOT the Mullvad VPN client (that's Gluetun in the acquisition stack).

resource "proxmox_virtual_environment_file" "wireguard_cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_file {
    path = "${path.module}/cloud-init/wireguard.yml"
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
}
