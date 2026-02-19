resource "proxmox_virtual_environment_vm" "docker_host" {
  name      = "gateway-wireguard"
  node_name = var.target_node
  started   = true
  on_boot   = true

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
        address = "10.0.0.116/24"
        gateway = "10.0.0.1"
      }
    }
    
    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }

  network_device {
    bridge = "vmbr0"
  }
}

resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.target_node

  source_raw {
    data = templatefile("${path.module}/cloud-init/user-data.yaml", {
      wireguard_server_url  = var.wireguard_server_url
      wireguard_server_port = var.wireguard_server_port
      wireguard_peers       = var.wireguard_peers
    })
    file_name = "user-data.yaml"
  }
}

output "docker_host_ip" {
  value = proxmox_virtual_environment_vm.docker_host.ipv4_addresses[1][0]
}