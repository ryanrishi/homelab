resource "aws_acm_certificate" "certificate" {
  domain_name               = var.root_domain_name
  validation_method         = "EMAIL"
  subject_alternative_names = ["*.${var.root_domain_name}"]

  lifecycle {
    create_before_destroy = true
  }
}
