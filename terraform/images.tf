locals {
  debian_image = "debian-13-generic-amd64-${var.debian_snapshot}.qcow2"
}

resource "proxmox_download_file" "debian" {
  for_each     = var.pve_nodes
  node_name    = each.key
  content_type = "import"
  datastore_id = "local"
  file_name    = local.debian_image

  url                = "https://cloud.debian.org/images/cloud/trixie/${var.debian_snapshot}/${local.debian_image}"
  checksum           = var.debian_checksum
  checksum_algorithm = "sha512"
}
