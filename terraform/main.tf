module "media" {
  source = "./modules/cloud_init"
  name   = "media"
  ip     = "192.168.4.201"

  cores     = 4
  sockets   = 2
  disk_size = 16
  memory    = 4096
  balloon   = 2048

  cloud_init_template_name = "debian-11-cloudinit-template"

  # NUC connection details (keep existing)
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}

module "wireguard" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.nuc
  }
  
  name        = "wireguard"
  ip          = "192.168.4.203"
  target_node = "ryanrishi"  # NUC node name

  cores   = 2
  sockets = 2
  memory  = 1024
  balloon = 512

  vm_state = "stopped"

  # NUC connection details
  pve_host     = var.pve_nuc_host
  pve_user     = var.pve_nuc_user
  pve_password = var.pve_nuc_password
}

module "ddclient" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.nuc
  }
  
  name        = "ddclient"
  target_node = "ryanrishi"  # NUC node name

  cores   = 1
  sockets = 1
  memory  = 512

  # NUC connection details
  pve_host     = var.pve_nuc_host
  pve_user     = var.pve_nuc_user
  pve_password = var.pve_nuc_password
}

locals {
  k3s_server_count = 3
}

resource "random_password" "password" {
  length  = 16
  special = false
}

module "k3s-server-0" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.nuc
  }
  
  name        = "k3s-server-0"
  target_node = "ryanrishi"  # NUC node name

  cores     = 2
  sockets   = 2
  memory    = 2048
  disk_size = 20

  additional_cloud_init_config = <<-EOT
  ansible:
    install_method: distro
    package_name: ansible-core
    pull:
      url: https://github.com/ryanrishi/homelab.git
      checkout: main
      playbook_name: k3s-server.yml
      extra_vars:
        cluster_init: true
        num_servers: ${local.k3s_server_count}
        token: ${random_password.password.result}

  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules:
    - package-update-upgrade-install
    - fan
    - landscape
    - lxd
    - write-files-deferred
    - puppet
    - chef
    - ansible  # added by ryanrishi
    - mcollective
    - salt-minion
    - reset_rmc
    - refresh_rmc_and_interface
    - rightscale_userdata
    - scripts-vendor
    - scripts-per-once
    - scripts-per-boot
    - scripts-per-instance
    - scripts-user
    - ssh-authkey-fingerprints
    - keys-to-console
    - install-hotplug
    - phone-home
    - final-message
    - power-state-change
  EOT

  # NUC connection details
  pve_host     = var.pve_nuc_host
  pve_user     = var.pve_nuc_user
  pve_password = var.pve_nuc_password
}

module "k3s-server-1" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.m720s
  }
  
  name        = "k3s-server-1"
  target_node = "pve001"  # M720s node name

  cores     = 2
  sockets   = 2
  memory    = 2048
  disk_size = 20

  additional_cloud_init_config = <<-EOT
  ansible:
    install_method: distro
    package_name: ansible-core
    pull:
      url: https://github.com/ryanrishi/homelab.git
      checkout: main
      playbook_name: k3s-server.yml
      extra_vars:
        cluster_init: false
        num_servers: ${local.k3s_server_count}
        token: ${random_password.password.result}

  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules:
    - package-update-upgrade-install
    - fan
    - landscape
    - lxd
    - write-files-deferred
    - puppet
    - chef
    - ansible  # added by ryanrishi
    - mcollective
    - salt-minion
    - reset_rmc
    - refresh_rmc_and_interface
    - rightscale_userdata
    - scripts-vendor
    - scripts-per-once
    - scripts-per-boot
    - scripts-per-instance
    - scripts-user
    - ssh-authkey-fingerprints
    - keys-to-console
    - install-hotplug
    - phone-home
    - final-message
    - power-state-change
  EOT

  # M720s connection details
  pve_host     = var.pve_m720s_host
  pve_user     = var.pve_m720s_user
  pve_password = var.pve_m720s_password

  depends_on = [
    module.k3s-server-0
  ]
}

module "k3s-server-2" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.m720s
  }
  
  name        = "k3s-server-2"
  target_node = "pve001"  # M720s node name

  cores     = 2
  sockets   = 2
  memory    = 2048
  disk_size = 20

  additional_cloud_init_config = <<-EOT
  ansible:
    install_method: distro
    package_name: ansible-core
    pull:
      url: https://github.com/ryanrishi/homelab.git
      checkout: main
      playbook_name: k3s-server.yml
      extra_vars:
        cluster_init: false
        num_servers: ${local.k3s_server_count}
        token: ${random_password.password.result}

  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules:
    - package-update-upgrade-install
    - fan
    - landscape
    - lxd
    - write-files-deferred
    - puppet
    - chef
    - ansible  # added by ryanrishi
    - mcollective
    - salt-minion
    - reset_rmc
    - refresh_rmc_and_interface
    - rightscale_userdata
    - scripts-vendor
    - scripts-per-once
    - scripts-per-boot
    - scripts-per-instance
    - scripts-user
    - ssh-authkey-fingerprints
    - keys-to-console
    - install-hotplug
    - phone-home
    - final-message
    - power-state-change
  EOT

  # M720s connection details
  pve_host     = var.pve_m720s_host
  pve_user     = var.pve_m720s_user
  pve_password = var.pve_m720s_password

  depends_on = [
    module.k3s-server-0
  ]
}

module "k3s-replica-0" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.nuc
  }
  
  name        = "k3s-replica-0"
  target_node = "ryanrishi"  # NUC node name

  cores     = 2
  sockets   = 2
  memory    = 4096
  disk_size = 20

  additional_cloud_init_config = <<-EOT
  ansible:
    install_method: distro
    package_name: ansible-core
    pull:
      url: https://github.com/ryanrishi/homelab.git
      checkout: main
      playbook_name: k3s-agent.yml
      extra_vars:
        token: ${random_password.password.result}

  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules:
    - package-update-upgrade-install
    - fan
    - landscape
    - lxd
    - write-files-deferred
    - puppet
    - chef
    - ansible  # added by ryanrishi
    - mcollective
    - salt-minion
    - reset_rmc
    - refresh_rmc_and_interface
    - rightscale_userdata
    - scripts-vendor
    - scripts-per-once
    - scripts-per-boot
    - scripts-per-instance
    - scripts-user
    - ssh-authkey-fingerprints
    - keys-to-console
    - install-hotplug
    - phone-home
    - final-message
    - power-state-change
  EOT

  # NUC connection details
  pve_host     = var.pve_nuc_host
  pve_user     = var.pve_nuc_user
  pve_password = var.pve_nuc_password

  depends_on = [
    module.k3s-server-0,
    module.k3s-server-1,
    module.k3s-server-2
  ]
}

module "k3s-replica-1" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.m720s
  }
  
  name        = "k3s-replica-1"
  target_node = "pve001"  # M720s node name

  cores     = 2
  sockets   = 2
  memory    = 4096
  disk_size = 20

  additional_cloud_init_config = <<-EOT
  ansible:
    install_method: distro
    package_name: ansible-core
    pull:
      url: https://github.com/ryanrishi/homelab.git
      checkout: main
      playbook_name: k3s-agent.yml
      extra_vars:
        token: ${random_password.password.result}

  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules:
    - package-update-upgrade-install
    - fan
    - landscape
    - lxd
    - write-files-deferred
    - puppet
    - chef
    - ansible  # added by ryanrishi
    - mcollective
    - salt-minion
    - reset_rmc
    - refresh_rmc_and_interface
    - rightscale_userdata
    - scripts-vendor
    - scripts-per-once
    - scripts-per-boot
    - scripts-per-instance
    - scripts-user
    - ssh-authkey-fingerprints
    - keys-to-console
    - install-hotplug
    - phone-home
    - final-message
    - power-state-change
  EOT

  # M720s connection details
  pve_host     = var.pve_m720s_host
  pve_user     = var.pve_m720s_user
  pve_password = var.pve_m720s_password

  depends_on = [
    module.k3s-server-0,
    module.k3s-server-1,
    module.k3s-server-2
  ]
}

module "k3s-replica-2" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.m720s
  }
  
  name        = "k3s-replica-2"
  target_node = "pve001"  # M720s node name

  cores     = 2
  sockets   = 2
  memory    = 4096
  disk_size = 20

  additional_cloud_init_config = <<-EOT
  ansible:
    install_method: distro
    package_name: ansible-core
    pull:
      url: https://github.com/ryanrishi/homelab.git
      checkout: main
      playbook_name: k3s-agent.yml
      extra_vars:
        token: ${random_password.password.result}

  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules:
    - package-update-upgrade-install
    - fan
    - landscape
    - lxd
    - write-files-deferred
    - puppet
    - chef
    - ansible  # added by ryanrishi
    - mcollective
    - salt-minion
    - reset_rmc
    - refresh_rmc_and_interface
    - rightscale_userdata
    - scripts-vendor
    - scripts-per-once
    - scripts-per-boot
    - scripts-per-instance
    - scripts-user
    - ssh-authkey-fingerprints
    - keys-to-console
    - install-hotplug
    - phone-home
    - final-message
    - power-state-change
  EOT

  # M720s connection details
  pve_host     = var.pve_m720s_host
  pve_user     = var.pve_m720s_user
  pve_password = var.pve_m720s_password

  depends_on = [
    module.k3s-server-0,
    module.k3s-server-1,
    module.k3s-server-2
  ]
}

module "k3s-replica-3" {
  source = "./modules/cloud_init"
  providers = {
    proxmox = proxmox.m720s
  }
  
  name        = "k3s-replica-3"
  target_node = "pve001"  # M720s node name

  cores     = 2
  sockets   = 2
  memory    = 4096
  disk_size = 20

  additional_cloud_init_config = <<-EOT
  ansible:
    install_method: distro
    package_name: ansible-core
    pull:
      url: https://github.com/ryanrishi/homelab.git
      checkout: main
      playbook_name: k3s-agent.yml
      extra_vars:
        token: ${random_password.password.result}

  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules:
    - package-update-upgrade-install
    - fan
    - landscape
    - lxd
    - write-files-deferred
    - puppet
    - chef
    - ansible  # added by ryanrishi
    - mcollective
    - salt-minion
    - reset_rmc
    - refresh_rmc_and_interface
    - rightscale_userdata
    - scripts-vendor
    - scripts-per-once
    - scripts-per-boot
    - scripts-per-instance
    - scripts-user
    - ssh-authkey-fingerprints
    - keys-to-console
    - install-hotplug
    - phone-home
    - final-message
    - power-state-change
  EOT

  # M720s connection details
  pve_host     = var.pve_m720s_host
  pve_user     = var.pve_m720s_user
  pve_password = var.pve_m720s_password

  depends_on = [
    module.k3s-server-0,
    module.k3s-server-1,
    module.k3s-server-2
  ]
}
