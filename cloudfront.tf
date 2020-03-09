resource "aws_cloudfront_distribution" "www_distribution" {
  origin {
    domain_name = aws_s3_bucket.www.website_endpoint
    origin_id   = var.www_domain_name

    custom_origin_config {
      http_port               = "80"
      https_port              = "443"
      origin_protocol_policy  = "http-only"
      origin_ssl_protocols    = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true

  default_cache_behavior {
    viewer_protocol_policy  = "redirect-to-https"
    compress                = true
    allowed_methods         = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = var.www_domain_name
    min_ttl                 = 0
    default_ttl             = 86400
    max_ttl                 = 31536000

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  aliases = [var.www_domain_name]

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.ryanrishi-com-logs.bucket_domain_name
    prefix          = "${var.www_domain_name}/cloudfront"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.certificate.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_cloudfront_distribution" "ryanrishi-com" {
  origin {
    domain_name = aws_s3_bucket.ryanrishi-com.website_endpoint
    origin_id   = var.root_domain_name

    custom_origin_config {
      http_port               = "80"
      https_port              = "443"
      origin_protocol_policy  = "http-only"
      origin_ssl_protocols    = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true

  default_cache_behavior {
    viewer_protocol_policy  = "redirect-to-https"
    compress                = true
    allowed_methods         = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = var.root_domain_name
    min_ttl                 = 0
    default_ttl             = 86400
    max_ttl                 = 31536000

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  aliases = [var.root_domain_name]

  logging_config {
    include_cookies = false
    bucket          = aws_s3_bucket.ryanrishi-com-logs.bucket_domain_name
    prefix          = "${var.root_domain_name}/cloudfront"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.certificate.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_cloudfront_distribution" "stage_distribution" {
  origin {
    domain_name = aws_s3_bucket.stage_ryanrishi_com.website_endpoint
    origin_id   = var.stage_domain_name

    custom_origin_config {
      http_port               = "80"
      https_port              = "443"
      origin_protocol_policy  = "http-only"
      origin_ssl_protocols    = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  enabled             = true

  default_cache_behavior {
    viewer_protocol_policy  = "redirect-to-https"
    compress                = true
    allowed_methods         = ["GET", "HEAD"]
    cached_methods          = ["GET", "HEAD"]
    target_origin_id        = var.stage_domain_name
    min_ttl                 = 0
    default_ttl             = 86400
    max_ttl                 = 31536000

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  aliases = [var.stage_domain_name]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.certificate.arn
    ssl_support_method  = "sni-only"
  }
}
