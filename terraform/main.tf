locals {
  cloud_init_template = "debian-11-cloudinit-template"
}

resource "proxmox_vm_qemu" "cloud-init-test" {
  target_node      = "ryanrishi"
  name             = "cloud-init-test"
  full_clone       = false
  memory           = 2048
  onboot           = true
  oncreate         = false
  automatic_reboot = true
  scsihw           = "virtio-scsi-pci"
  clone            = local.cloud_init_template

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = "2G"
  }

  network {
    bridge = "vmbr0"
    model  = "virtio"
  }

  sshkeys = <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMO+4LbsTRGGW2SO0F5q7WLuOCCGW/wSbMPgIo1wO0/1 ryan@ryanrishi.com
EOF

}

