resource "proxmox_vm_qemu" "cloud-init-test" {
  target_node      = var.target_node
  name             = var.name
  full_clone       = false
  memory           = var.memory
  automatic_reboot = true
  scsihw           = "virtio-scsi-pci"
  clone            = var.cloud_init_template_name
  os_type          = "cloud-init"
  ipconfig0        = "ip=${var.ip}/24,gw=${var.gateway}"
  cicustom         = "user=snippets:snippets/user_data_vm-${var.name}.yml"

  disk {
    type    = "scsi"
    storage = "local-lvm"
    size    = var.disk_size
  }

  network {
    bridge = "vmbr0"
    model  = "virtio"
  }

  depends_on = [
    null_resource.cloud_init_config_files
  ]
}

resource "local_file" "cloud_init_user_data" {
  content = templatefile("${path.module}/cloud-init.tftpl", {
    hostname = var.name
    users    = var.users
  })
  filename = "${path.module}/files/user_data_${var.name}.yml"
}

resource "null_resource" "cloud_init_config_files" {
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
