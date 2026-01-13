module "media" {
  source = "./modules/cloud_init"
  name   = "media"
  ip     = "192.168.4.201"

  cores     = 4
  sockets   = 2
  disk_size = 16
  memory    = 8192
  balloon   = 0

  cloud_init_template_name = "debian-11-cloudinit-template"
  target_node              = "ryanrishi"

  pve_user     = var.pve_user
  pve_password = var.pve_password
}

locals {
  k3s_server_count  = 4
  k3s_replica_count = 3

  # K3s server configurations
  k3s_servers = {
    0 = { target_node = "ryanrishi", cluster_init = false, ip = "192.168.4.65" }
    1 = { target_node = "pve001" }
    2 = { target_node = "ryanrishi" }
    3 = { target_node = "pve001" }
  }

  # K3s replica configurations
  k3s_replicas = {
    0 = { target_node = "ryanrishi" }
    1 = { target_node = "pve001" }
    2 = { target_node = "ryanrishi" }
  }

  # Common cloud-init modules list
  cloud_final_modules = [
    "package-update-upgrade-install",
    "fan",
    "landscape",
    "lxd",
    "write-files-deferred",
    "puppet",
    "chef",
    "ansible", # added by ryanrishi
    "mcollective",
    "salt-minion",
    "reset_rmc",
    "scripts-vendor",
    "scripts-per-once",
    "scripts-per-boot",
    "scripts-per-instance",
    "scripts-user",
    "ssh-authkey-fingerprints",
    "keys-to-console",
    "install-hotplug",
    "phone-home",
    "final-message",
    "power-state-change"
  ]
}

resource "random_password" "password" {
  length  = 16
  special = false
}

# K3s server nodes
module "k3s-servers" {
  source = "./modules/cloud_init"
  count  = local.k3s_server_count

  name        = "k3s-server-${count.index}"
  target_node = local.k3s_servers[count.index].target_node
  ip          = lookup(local.k3s_servers[count.index], "ip", null)

  cores     = 2
  sockets   = 2
  memory    = 2048
  disk_size = 20
  balloon   = 0

  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password

  additional_cloud_init_config = yamlencode({
    ansible = {
      install_method = "distro"
      package_name   = "ansible-core"
      pull = {
        url           = "https://github.com/ryanrishi/homelab.git"
        checkout      = "main"
        playbook_name = "k3s-server.yml"
        extra_vars = {
          cluster_init = lookup(local.k3s_servers[count.index], "cluster_init", false)
          token        = random_password.password.result
        }
      }
    }

    # Unfortunately `cloud_final_modules` can't be merged, only overwritten
    # This is the list from /etc/cloud/cloud.cfg with `ansible` added
    cloud_final_modules = local.cloud_final_modules
  })

}

# K3s replica nodes (agents)
module "k3s-replicas" {
  source = "./modules/cloud_init"
  count  = local.k3s_replica_count

  name        = "k3s-replica-${count.index}"
  target_node = local.k3s_replicas[count.index].target_node

  cores     = 2
  sockets   = 2
  memory    = 4096
  disk_size = 20
  balloon   = 0

  additional_cloud_init_config = yamlencode({
    ansible = {
      install_method = "distro"
      package_name   = "ansible-core"
      pull = {
        url           = "https://github.com/ryanrishi/homelab.git"
        checkout      = "main"
        playbook_name = "k3s-agent.yml"
        extra_vars = {
          token = random_password.password.result
        }
      }
    }

    # Unfortunately `cloud_final_modules` can't be merged, only overwritten
    # This is the list from /etc/cloud/cloud.cfg with `ansible` added
    cloud_final_modules = local.cloud_final_modules
  })

  depends_on = [module.k3s-servers[0]]

  pve_user     = var.pve_user
  pve_password = var.pve_password
}
