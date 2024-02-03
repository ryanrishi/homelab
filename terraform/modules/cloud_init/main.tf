resource "proxmox_vm_qemu" "vm" {
  target_node      = var.target_node
  name             = var.name
  bios             = var.bios
  qemu_os          = "other"
  full_clone       = false
  cores            = var.cores
  sockets          = var.sockets
  memory           = var.memory
  balloon          = var.balloon
  agent            = var.agent
  automatic_reboot = true
  onboot           = var.onboot
  vm_state         = var.vm_state
  scsihw           = "virtio-scsi-pci"
  clone            = var.cloud_init_template_name
  os_type          = "cloud-init"
  ipconfig0        = var.ip == null ? "ip=dhcp" : "ip=${var.ip}/24,gw=${var.gateway}"
  cicustom         = "user=snippets:snippets/user_data_vm-${var.name}.yml"

  cloudinit_cdrom_storage = "local-lvm"

  nameserver   = var.nameserver
  searchdomain = var.searchdomain

  disks {
    scsi {
      scsi0 {
        disk {
          storage   = "local-lvm"
          size      = var.disk_size
          replicate = true
        }
      }
    }
  }

  network {
    bridge = "vmbr0"
    model  = "virtio"
  }

  depends_on = [
    null_resource.cloud_init_user_data
  ]

  lifecycle {
    ignore_changes = [clone]
  }
}

resource "local_file" "cloud_init_user_data" {
  content = templatefile("${path.module}/cloud-init.tftpl", {
    hostname = var.name
    users    = var.users
  })
  filename = "${path.module}/files/user_data_${var.name}.yml"
}

resource "null_resource" "cloud_init_user_data" {
  connection {
    type     = "ssh"
    user     = var.pve_user
    password = var.pve_password
    host     = var.pve_host
  }

  provisioner "file" {
    source      = local_file.cloud_init_user_data.filename
    destination = "/snippets/snippets/user_data_vm-${var.name}.yml"
  }

  triggers = {
    cloud_init_user_data = local_file.cloud_init_user_data.content_md5
  }
}
