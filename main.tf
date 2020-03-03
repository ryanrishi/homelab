terraform {
  backend "s3" {
    bucket  = "ryanrishi-terraform-test"
    key     = "terraform/key"
    region  = "us-east-1"
  }
}
