# resource "proxmox_vm_qemu" "cloud-init-test" {
#   target_node = "ryanrishi"
#   name        = "cloud-init-test"
#   full_clone  = false
#   memory      = 2048
#   onboot      = true
#   # oncreate         = false
#   automatic_reboot = true
#   scsihw           = "virtio-scsi-pci"
#   clone            = local.cloud_init_template
#   os_type          = "cloud-init"
#   ipconfig0        = "ip=192.168.1.201/24,gw=192.168.1.1"
#   # cicustom =

#   disk {
#     type    = "scsi"
#     storage = "local-lvm"
#     size    = "2G"
#   }

#   network {
#     bridge = "vmbr0"
#     model  = "virtio"
#   }

#   sshkeys = <<EOF
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMO+4LbsTRGGW2SO0F5q7WLuOCCGW/wSbMPgIo1wO0/1 ryan@ryanrishi.com
# EOF
# }

module "test" {
  source = "./modules/cloud_init"
  name   = "cloud-init-test"
  ip     = "192.168.1.201"

  # TODO I really don't like passing this in to every VM... is there a better way to get cloud-init configs into PVE?
  pve_host     = var.pve_host
  pve_user     = var.pve_user
  pve_password = var.pve_password
}
