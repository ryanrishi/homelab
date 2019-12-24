provider "aws" {
  region = "us-east-1"
  profile = "ryanrishi"
}

data "aws_caller_identity" "current" {}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "caller_arn" {
  value = data.aws_caller_identity.current.arn
}

output "caller_user" {
  value = data.aws_caller_identity.current.user_id
}

variable "www_domain_name" {
  default = "www.ryanrishi.com"
}

variable "root_domain_name" {
  default = "ryanrishi.com"
}

resource "aws_s3_bucket" "www" {
  bucket = var.www_domain_name
  acl    = "public-read"
  policy = <<POLICY
  {
    "Version": "2019-12-23",
    "Statement": [
      {
        "Sid": "AddPerm",
        "Effect": "Allow",
        "Principal": "*",
        "Action": ["s3:GetObject"],
        "Resource": ["arn:aws:s3:::${var.www_domain_name}/*"]
      }
    ]
  }
POLICY

  website {
    index_document = "index.html"
    error_document = "404.html"
  }
}