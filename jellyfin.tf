# ==============================================================================
# Jellyfin Media Server — Unprivileged LXC
# ==============================================================================
# Runs Jellyfin natively (not Docker) for best performance with GPU passthrough.
# The integrated GPU (/dev/dri/renderD128) is passed through for hardware
# transcoding. Storage is bind-mounted from the Proxmox host.
#
# After `tofu apply`, access Jellyfin at: http://10.0.0.33:8096
# (or via jellyfin.alexanderwest.com once NPM proxy host is configured)

resource "proxmox_virtual_environment_container" "jellyfin" {
  description = "Jellyfin media server with GPU transcoding"
  node_name   = var.target_node
  vm_id       = 102

  operating_system {
    template_file_id = local.lxc_template_id
    type             = "debian"
  }

  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "jellyfin"

    ip_config {
      ipv4 {
        address = "${var.jellyfin_ip}/${var.network_cidr}"
        gateway = var.network_gateway
      }
    }

    user_account {
      keys     = [var.ssh_public_key]
      password = "changeme"
    }
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    size         = 8
  }

  # NOTE: Bind mount is added post-creation via null_resource below,
  # because API tokens lack permission for mount_point (root@pam only).

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  start_on_boot = true

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].password]
  }
}

# --- Post-provision: bind mount, GPU passthrough, install Jellyfin ------------
# Everything is automated via pct commands over SSH to the Proxmox host.

resource "null_resource" "jellyfin_setup" {
  depends_on = [proxmox_virtual_environment_container.jellyfin]

  triggers = {
    container_id = proxmox_virtual_environment_container.jellyfin.vm_id
  }

  connection {
    type         = "ssh"
    host         = var.proxmox_host_ip
    user         = "root"
    agent        = true
    bastion_host = "98.51.110.156"
    bastion_port = 52222
    bastion_user = "root"
  }

  provisioner "remote-exec" {
    inline = [
      "sleep 5",

      # --- Bind mount: host storage → container /mnt/storage ----------------------
      # API tokens can't create bind mounts, so we add it via pct set as root@pam.
      # Create host dir if missing, then attach it to the container.
      "mkdir -p ${var.storage_host_path}",
      "pct set ${proxmox_virtual_environment_container.jellyfin.vm_id} -mp0 ${var.storage_host_path},mp=/mnt/storage",

      # --- GPU passthrough for hardware transcoding --------------------------------
      "grep -q 'lxc.cgroup2.devices.allow.*226:128' /etc/pve/lxc/${proxmox_virtual_environment_container.jellyfin.vm_id}.conf || echo 'lxc.cgroup2.devices.allow: c 226:128 rwm' >> /etc/pve/lxc/${proxmox_virtual_environment_container.jellyfin.vm_id}.conf",
      "grep -q 'lxc.mount.entry.*renderD128' /etc/pve/lxc/${proxmox_virtual_environment_container.jellyfin.vm_id}.conf || echo 'lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file' >> /etc/pve/lxc/${proxmox_virtual_environment_container.jellyfin.vm_id}.conf",

      # Reboot so mount + GPU changes take effect
      "pct reboot ${proxmox_virtual_environment_container.jellyfin.vm_id}",
      "sleep 10",

      # Install Jellyfin from official apt repo (non-interactive, no script prompt)
      "pct exec ${proxmox_virtual_environment_container.jellyfin.vm_id} -- bash -c 'apt-get update && apt-get install -y curl gnupg apt-transport-https'",
      "pct exec ${proxmox_virtual_environment_container.jellyfin.vm_id} -- bash -c 'mkdir -p /etc/apt/keyrings && curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg'",
      "pct exec ${proxmox_virtual_environment_container.jellyfin.vm_id} -- bash -c 'echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/jellyfin.gpg] https://repo.jellyfin.org/debian bookworm main\" > /etc/apt/sources.list.d/jellyfin.list'",
      "pct exec ${proxmox_virtual_environment_container.jellyfin.vm_id} -- bash -c 'apt-get update && apt-get install -y jellyfin'",

      # Create media directory structure
      "pct exec ${proxmox_virtual_environment_container.jellyfin.vm_id} -- bash -c 'mkdir -p /mnt/storage/media/movies /mnt/storage/media/shows'",

      # Enable and start Jellyfin
      "pct exec ${proxmox_virtual_environment_container.jellyfin.vm_id} -- bash -c 'systemctl enable --now jellyfin'",
    ]
  }
}
