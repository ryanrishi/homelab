variable "name" {
  type = string
}

variable "node_name" {
  type = string
}

variable "image_file_id" {
  type = string
}

variable "cores" {
  default = 2
}

variable "sockets" {
  default = 2
}

variable "memory" {
  default = 2048
}

variable "disk_size" {
  default = 20
}

variable "data_disk_size" {
  default = 0
}

variable "datastore_id" {
  default = "local-lvm"
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
  type = string
}

variable "users" {
  type = map(object({ ssh_key = string }))
}

variable "additional_cloud_init_config" {
  default = ""
}
