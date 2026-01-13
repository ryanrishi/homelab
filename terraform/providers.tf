terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc1"
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
