variable "name" {
  type = string
}

variable "target_node" {
  default = "ryanrishi"
}

variable "users" {
  type = map(any)
  default = {
    ryan = {
      ssh_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMO+4LbsTRGGW2SO0F5q7WLuOCCGW/wSbMPgIo1wO0/1 ryan@ryanrishi.com"
    }
  }
}

variable "cloud_init_template_name" {
  default = "debian-12-generic"
}

variable "cores" {
  default = 1
}

variable "sockets" {
  default = 1
}

variable "memory" {
  default = 2048
}

variable "balloon" {
  default = 512
}

variable "disk_size" {
  description = "Disk size, in gigabytes"
  default     = 4
}

variable "bios" {
  default = "ovmf"
}

variable "onboot" {
  default = true
}

variable "oncreate" {
  default = true
}

variable "vm_state" {
  default = "running"
}

variable "agent" {
  default = 1
}

variable "ip" {
  type    = string
  default = null
}

variable "gateway" {
  default = "192.168.4.1"
}

variable "nameserver" {
  default = "192.168.4.1"
}

variable "searchdomain" {
  default = "nyc.ccag119.info"
}

variable "additional_cloud_init_config" {
  type    = string
  default = ""
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
