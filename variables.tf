variable "region" {
  default = "us-east-1"
}

variable "www_domain_name" {}

variable "root_domain_name" {}

variable "workspace_to_domain_name" {
  default = {
    production = "ryanrishi.com"
    staging    = "stage.ryanrishi.com"
  }
}

variable "covid_19_origin_domain_name" {
  default = "ec2-xxx-xxx-xxx-xxx.compute-1.amazonaws.com"
}

locals {
  domain_name = lookup(var.workspace_to_domain_name, terraform.workspace)
}
