terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc1"
    }
    pve = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }
}

# Default provider (cluster-aware)
provider "proxmox" {
  pm_api_url    = "https://${var.pve_host}:8006/api2/json"
  pm_user       = "${var.pve_user}@pam"
  pm_password   = var.pve_password
  pm_log_enable = true
  pm_debug      = true
}

provider "pve" {
  endpoint = "https://${var.pve_host}:8006/"
  username = "${var.pve_user}@pam"
  password = var.pve_password
  insecure = true

  # Snippet uploads have no API equivalent, so the provider shells out over SSH.
  # Node addresses are listed explicitly because the hostnames do not resolve.
  # Credentials come from PROXMOX_VE_SSH_PRIVATE_KEY (see .env).
  ssh {
    username = "root"

    dynamic "node" {
      for_each = var.pve_nodes
      content {
        name    = node.key
        address = node.value
      }
    }
  }
}
