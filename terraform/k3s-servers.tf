# Keyed by a stable logical id rather than the Proxmox node, so a server can be
# moved between nodes without Terraform replacing it, and so more than one server
# per node stays expressible.
locals {
  k3s_control_plane = {
    alpha = { node = "pve003", memory = 4096 }
  }
}

# Randomised so a rebuilt server joins etcd under a new member name instead of
# colliding with the departing one.
resource "random_string" "k3s_server" {
  for_each = local.k3s_control_plane
  length   = 6
  special  = false
  upper    = false
}

module "k3s_servers" {
  source   = "./modules/vm"
  for_each = local.k3s_control_plane

  name          = "k3s-server-${random_string.k3s_server[each.key].result}"
  node_name     = each.value.node
  image_file_id = proxmox_download_file.debian[each.value.node].id

  memory    = each.value.memory
  disk_size = 20

  users        = var.users
  searchdomain = var.searchdomain

  additional_cloud_init_config = yamlencode({
    ansible = {
      install_method = "distro"
      package_name   = "ansible-core"
      pull = {
        url           = "https://github.com/ryanrishi/homelab.git"
        checkout      = "main"
        playbook_name = "k3s-server.yml"
        extra_vars = {
          cluster_init = false
          token        = random_password.password.result
        }
      }
    }

    # Unfortunately `cloud_final_modules` can't be merged, only overwritten
    # This is the list from /etc/cloud/cloud.cfg with `ansible` added
    cloud_final_modules = local.cloud_final_modules
  })
}
