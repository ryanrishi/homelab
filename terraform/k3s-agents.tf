locals {
  k3s_agents = [
    { node = "pve003", memory = 4096, igpu = true },
    { node = "pve003", memory = 4096 },
  ]

  longhorn_node_labels = [
    "--node-label lab.ryanrishi.com/longhorn-enabled=true",
    "--node-label node.longhorn.io/create-default-disk=true",
  ]

  igpu_node_label = ["--node-label lab.ryanrishi.com/gpu-enabled=true"]
}

resource "random_string" "k3s_agent" {
  count   = length(local.k3s_agents)
  length  = 6
  special = false
  upper   = false
}

module "k3s_agents" {
  source = "./modules/vm"
  count  = length(local.k3s_agents)

  name          = "k3s-agent-${random_string.k3s_agent[count.index].result}"
  node_name     = local.k3s_agents[count.index].node
  image_file_id = proxmox_download_file.debian[local.k3s_agents[count.index].node].id

  memory         = local.k3s_agents[count.index].memory
  disk_size      = 20
  data_disk_size = 30

  hostpci_mapping = try(local.k3s_agents[count.index].igpu, false) ? proxmox_hardware_mapping_pci.igpu.name : null

  users        = var.users
  searchdomain = var.searchdomain

  additional_cloud_init_config = yamlencode({
    ansible = {
      install_method = "distro"
      package_name   = "ansible-core"
      pull = {
        url           = "https://github.com/ryanrishi/homelab.git"
        checkout      = "main"
        playbook_name = "k3s-agent.yml"
        extra_vars = {
          token = random_password.password.result

          # Join through the control-plane VIP rather than a single server
          k3s_server_endpoint = var.kube_vip_address

          extra_agent_args = join(" ", concat(
            local.longhorn_node_labels,
            try(local.k3s_agents[count.index].igpu, false) ? local.igpu_node_label : [],
          ))
        }
      }
    }

    # Unfortunately `cloud_final_modules` can't be merged, only overwritten
    # This is the list from /etc/cloud/cloud.cfg with `ansible` added
    cloud_final_modules = local.cloud_final_modules
  })
}
