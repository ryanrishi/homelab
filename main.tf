terraform {
  backend "s3" {
    bucket = "ryanrishi-terraform-test"
    key    = "ryanrishi-com/terraform.tfstate"
    region = "us-east-1"
  }
}
