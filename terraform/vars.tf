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
  default = "735d1b2d0ef265a0c2323fdaa7d46e7bd7a1b984f73e8a785e638034bf07876e26374a9d809d713501270c071b3464d2ada0c5589f07742b95ed853cc6d48f45"
}
