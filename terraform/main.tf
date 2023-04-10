module "media" {
  source = "./modules/cloud_init"
  name   = "media"
  ip     = "192.168.1.201"

  cores     = 8
  disk_size = "8G"
  memory    = 8192
  balloon   = 2048

  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}
