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
