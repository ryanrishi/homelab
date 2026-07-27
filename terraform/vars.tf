variable "pve_host" {
  default = "192.168.1.192"
}

variable "pve_user" {
  default = "terraform"
}

variable "pve_password" {
  type      = string
  sensitive = true
}

variable "pve_nodes" {
  type = map(string)
  default = {
    ryanrishi = "192.168.4.200"
    pve002    = "192.168.4.202"
    pve003    = "192.168.4.203"
  }
}

variable "searchdomain" {
  type = string
}

variable "kube_vip_address" {
  default = "192.168.4.5"
}


variable "users" {
  type = map(object({ ssh_key = string }))
  default = {
    ryan = {
      ssh_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMO+4LbsTRGGW2SO0F5q7WLuOCCGW/wSbMPgIo1wO0/1 ryan@ryanrishi.com"
    }
  }
}

variable "debian_snapshot" {
  default = "20260722-2547"
}

variable "debian_checksum" {
  default = "1ff07be8406c4abcb75662a351b6124408c4a2795801037f8e4fe9ee27084ee2112bef92222f4bbeb9f7df8df1062971a9692f4c82f3da3c01fda6b1493906b9"
}
