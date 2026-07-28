# Intel display controllers, discovered per node rather than hardcoded.
data "proxmox_hardware_pci" "igpu" {
  for_each  = var.pve_nodes
  node_name = each.key

  filters = {
    class     = "03"   # display controllers
    vendor_id = "8086" # Intel
  }
}

locals {
  # Only nodes that actually have one. Adding a node with an Intel iGPU picks it
  # up automatically; a node without one is simply absent from the mapping.
  igpu_devices = {
    for node, hw in data.proxmox_hardware_pci.igpu : node => hw.devices[0]
    if length(hw.devices) > 0
  }
}

# A mapped device can be assigned by a non-root API user, unlike a raw hostpci
# path, so guests can claim the GPU through Terraform instead of `qm set` as root.
resource "proxmox_hardware_mapping_pci" "igpu" {
  name     = "igpu"
  comment  = "Managed by Terraform"

  map = [
    for node, device in local.igpu_devices : {
      node         = node
      path         = device.id
      iommu_group  = device.iommu_group
      id           = "${replace(device.vendor, "0x", "")}:${replace(device.device, "0x", "")}"
      subsystem_id = "${replace(device.subsystem_vendor, "0x", "")}:${replace(device.subsystem_device, "0x", "")}"
    }
  ]
}
