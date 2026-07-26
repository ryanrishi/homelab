locals {
  user_data = join("", [
    templatefile("${path.module}/cloud-init.tftpl", {
      hostname     = var.name
      users        = var.users
      nameserver   = var.nameserver
      searchdomain = var.searchdomain
    }),
    var.additional_cloud_init_config,
  ])
}

# The provider does not diff snippet contents, so the hash is part of the file
# name to make a content change produce a new file the VM then picks up.
resource "proxmox_virtual_environment_file" "user_data" {
  provider     = pve
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.node_name

  source_raw {
    data      = local.user_data
    file_name = "user-data-${var.name}-${substr(sha256(local.user_data), 0, 8)}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  provider      = pve
  name          = var.name
  node_name     = var.node_name
  on_boot       = true
  scsi_hardware = "virtio-scsi-pci"
  stop_on_destroy = true

  cpu {
    cores   = var.cores
    sockets = var.sockets
    type    = "host"
  }

  memory {
    dedicated = var.memory
    floating  = 0
  }

  agent {
    enabled = true
  }

  disk {
    datastore_id = var.datastore_id
    import_from  = var.image_file_id
    interface    = "scsi0"
    size         = var.disk_size
  }

  dynamic "disk" {
    for_each = var.data_disk_size > 0 ? [1] : []
    content {
      datastore_id = var.datastore_id
      interface    = "scsi1"
      size         = var.data_disk_size
    }
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = var.ip == null ? "dhcp" : "${var.ip}/24"
        gateway = var.ip == null ? null : var.gateway
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.user_data.id
  }

  operating_system {
    type = "l26"
  }
}
