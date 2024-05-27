module "media" {
  source = "./modules/cloud_init"
  name   = "media"
  ip     = "192.168.4.201"

  cores     = 4
  sockets   = 2
  disk_size = 16
  memory    = 8192
  balloon   = 2048

  cloud_init_template_name = "debian-11-cloudinit-template"

  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}

module "wireguard" {
  source = "./modules/cloud_init"
  name   = "wireguard"
  ip     = "192.168.4.203"

  cores   = 2
  sockets = 2
  memory  = 1024
  balloon = 512

  vm_state = "stopped"

  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}

module "ddclient" {
  source = "./modules/cloud_init"
  name   = "ddclient"

  cores   = 1
  sockets = 1
  memory  = 512

  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}

locals {
  k3s_server_count = 3
}

resource "random_password" "password" {
  length  = 16
  special = false
}

module "k3s-server" {
  count  = local.k3s_server_count
  source = "./modules/cloud_init"
  name   = "k3s-server-${count.index}"

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
        cluster_init: ${count.index == 0}
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

  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}

module "k3s-agent" {
  count  = 4
  source = "./modules/cloud_init"
  name   = "k3s-replica-${count.index}"

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


  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password

  depends_on = [
    module.k3s-server
  ]
}
