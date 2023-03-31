module "test" {
  source = "./modules/cloud_init"
  name   = "cloud-init-test"
  ip     = "192.168.1.201"

  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}
