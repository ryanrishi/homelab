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
