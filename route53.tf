resource "aws_route53_zone" "zone" {
  name = var.root_domain_name
}

resource "aws_route53_zone" "ccag119_info_zone" {
  name = "ccag119.info"
}

resource "aws_route53_record" "ccag119_info_ns" {
  name    = "ccag119.info"
  zone_id = aws_route53_zone.ccag119_info_zone.zone_id
  type    = "NS"
  ttl     = 60

  records = [
    "abby.ns.cloudflare.com.",
    "carter.ns.cloudflare.com."
  ]
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

resource "aws_route53_record" "dns_a" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = local.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cloudfront_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.cloudfront_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "labs" {
  zone_id = aws_route53_zone.zone.zone_id
  name    = "labs.${local.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.labs.domain_name
    zone_id                = aws_cloudfront_distribution.labs.hosted_zone_id
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
  name    = "ryanrishi.com"
  ttl     = 60
  type    = "NS"
  zone_id = aws_route53_zone.zone.zone_id

  records = [
    "${aws_route53_zone.zone.name_servers.0}.",
    "${aws_route53_zone.zone.name_servers.1}.",
    "${aws_route53_zone.zone.name_servers.2}.",
    "${aws_route53_zone.zone.name_servers.3}."
  ]
}
