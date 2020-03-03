terraform {
  backend "s3" {
    bucket  = "ryanrishi-terraform-test"
    key     = "terraform/key"
    region  = "us-east-1"
  }
}
resource "aws_route53_zone" "zone" {
  name = var.root_domain_name
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = var.www_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.www_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.www_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = var.root_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.ryanrishi-com.domain_name
    zone_id                = aws_cloudfront_distribution.ryanrishi-com.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "stage" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = var.stage_domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.stage_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.stage_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "mx-gsuite" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = var.root_domain_name
  type    = "MX"
  ttl     = 60

  records = [
    "1 aspmx.l.google.com",
    "5 alt1.aspmx.l.google.com",
    "5 alt2.aspmx.l.google.com",
    "10 alt3.aspmx.l.google.com",
    "10 alt4.aspmx.l.google.com",
  ]
}

resource "aws_route53_record" "ns" {
  name            = "ryanrishi.com"
  ttl             = 60
  type            = "NS"
  zone_id         = aws_route53_zone.zone.zone_id

  records = [
    "${aws_route53_zone.zone.name_servers.0}.",
    "${aws_route53_zone.zone.name_servers.1}.",
    "${aws_route53_zone.zone.name_servers.2}.",
    "${aws_route53_zone.zone.name_servers.3}."
  ]
}
