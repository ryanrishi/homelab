provider "aws" {
  region = "us-east-1"
  profile = "ryanrishi"
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