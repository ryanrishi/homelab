terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.1-rc1"
    }
  }
}

provider "proxmox" {
  pm_api_url    = "https://${var.pve_host}:8006/api2/json"
  pm_log_enable = true
  pm_debug      = true
}
