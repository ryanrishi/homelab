variable "name" {
  type = string
}

variable "target_node" {
  default = "ryanrishi"
}

variable "ssh_authorized_keys" {
  type = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMO+4LbsTRGGW2SO0F5q7WLuOCCGW/wSbMPgIo1wO0/1 ryan@ryanrishi.com"
  ]
}

variable "cloud_init_template_name" {
  default = "debian-11-cloudinit-template"
}

variable "memory" {
  default = 2048
}

variable "disk_size" {
  default = "2G"
}

variable "ip" {
  type = string
}

variable "gateway" {
  default = "192.168.1.1"
}

variable "pve_host" {
  default = "192.168.1.192"
}

variable "pve_user" {
  default = "terraform"
}

variable "pve_password" {
  default = "password"
}
