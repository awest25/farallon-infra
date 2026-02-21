# ==============================================================================
# Reverse Proxy — Nginx Proxy Manager + CrowdSec
# ==============================================================================
# This LXC sits on DHCP so your router can port-forward 80/443 to it.
# It terminates SSL via Let's Encrypt and routes subdomains to internal services.
# CrowdSec reads NPM access logs and drops malicious connections.
#
# After `tofu apply`, configure your router to port-forward:
#   TCP 80  → this container's DHCP IP
#   TCP 443 → this container's DHCP IP
#
# NPM admin panel: http://<container-ip>:81
#   Default login: admin@example.com / changeme

resource "proxmox_virtual_environment_container" "reverse_proxy" {
  description = "Nginx Proxy Manager + CrowdSec reverse proxy"
  node_name   = var.target_node
  vm_id       = 101

  # Debian 12 CT template (auto-detected and downloaded via pveam in main.tf)
  operating_system {
    template_file_id = local.lxc_template_id
    type             = "debian"
  }

  # Docker requires nesting
  features {
    nesting = true
  }

  # Unprivileged for security — nesting still works
  unprivileged = true

  initialization {
    hostname = "reverse-proxy"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys     = [var.ssh_public_key]
      password = "changeme" # Only used for console access; SSH key is primary
    }
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  start_on_boot = true

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].password]
  }
}

# --- Post-provision: install Docker + deploy NPM & CrowdSec ------------------
resource "null_resource" "reverse_proxy_setup" {
  depends_on = [proxmox_virtual_environment_container.reverse_proxy]

  triggers = {
    container_id = proxmox_virtual_environment_container.reverse_proxy.vm_id
  }

  connection {
    type  = "ssh"
    host  = var.proxmox_host_ip
    user  = "root"
    agent = true
  }

  # Wait for container to fully start
  provisioner "remote-exec" {
    inline = [
      "sleep 5",
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'apt-get update && apt-get install -y curl ca-certificates gnupg'",

      # Install Docker (official method)
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'install -m 0755 -d /etc/apt/keyrings'",
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && chmod a+r /etc/apt/keyrings/docker.asc'",
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list'",
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin'",

      # Write the docker-compose file
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'mkdir -p /opt/reverse-proxy/data/{npm,letsencrypt,crowdsec/config,crowdsec/data}'",
      <<-EOT
      pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'cat > /opt/reverse-proxy/docker-compose.yml << "COMPOSE"
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: npm
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - /opt/reverse-proxy/data/npm:/data
      - /opt/reverse-proxy/data/letsencrypt:/etc/letsencrypt
      - /var/log/npm:/data/logs

  crowdsec:
    image: crowdsecurity/crowdsec:latest
    container_name: crowdsec
    restart: unless-stopped
    environment:
      - COLLECTIONS=crowdsecurity/nginx-proxy-manager
    volumes:
      - /opt/reverse-proxy/data/crowdsec/config:/etc/crowdsec
      - /opt/reverse-proxy/data/crowdsec/data:/var/lib/crowdsec/data
      - /var/log/npm:/var/log/npm:ro
COMPOSE'
      EOT
      ,

      # Start the stack
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash -c 'cd /opt/reverse-proxy && docker compose up -d'",
    ]
  }
}

# --- Automate NPM proxy hosts via API ----------------------------------------
# Non-destructive: checks if NPM is already configured before setting up.
# Creates admin user on fresh installs, ensures all proxy hosts exist.
resource "null_resource" "npm_proxy_setup" {
  depends_on = [null_resource.reverse_proxy_setup]

  triggers = {
    proxy_config = jsonencode({
      domain         = var.domain
      jellyfin_ip    = var.jellyfin_ip
      acquisition_ip = var.acquisition_ip
    })
  }

  connection {
    type  = "ssh"
    host  = var.proxmox_host_ip
    user  = "root"
    agent = true
  }

  # Upload the rendered setup script into the LXC
  provisioner "remote-exec" {
    inline = [
      # Install jq in the LXC (needed for JSON parsing in the setup script)
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- apt-get install -y jq",
    ]
  }

  # Render the script with Terraform values and push it into the LXC
  provisioner "file" {
    content = templatefile("${path.module}/scripts/setup-npm.sh", {
      admin_email    = "admin@${var.domain}"
      admin_password = var.npm_admin_password
      domain         = var.domain
      jellyfin_ip    = var.jellyfin_ip
      acquisition_ip = var.acquisition_ip
    })
    destination = "/tmp/setup-npm.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "pct push ${proxmox_virtual_environment_container.reverse_proxy.vm_id} /tmp/setup-npm.sh /tmp/setup-npm.sh",
      "pct exec ${proxmox_virtual_environment_container.reverse_proxy.vm_id} -- bash /tmp/setup-npm.sh",
      "rm -f /tmp/setup-npm.sh",
    ]
  }
}
