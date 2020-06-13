resource "aws_s3_bucket" "s3_bucket" {
  bucket = local.domain_name
  acl    = "public-read"
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AddPerm",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject"],
      "Resource": ["arn:aws:s3:::${local.domain_name}/*"]
    }
  ]
}
POLICY

  website {
    index_document = "index.html"
    error_document = "404.html"
  }

  tags = {
    Environment = terraform.workspace
  }
}

resource "aws_s3_bucket" "ryanrishi-com-logs" {
  bucket = "${var.root_domain_name}-logs"
  acl    = "log-delivery-write"
}

resource "aws_s3_bucket" "www" {
  bucket = var.www_domain_name
  acl    = "public-read"
  policy = <<POLICY
{
  "Version": "2012-10-17",
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
    redirect_all_requests_to = "https://${var.root_domain_name}"
  }

  tags = {
    Environment = "production"
  }
}
