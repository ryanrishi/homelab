devops
===

Infrastructure-as-code using [Terraform](https://www.terraform.io/)

## Current Infrastructure
### ryanrishi.com
- S3
- CloudFront
- ACM for CloudFront distribution

## Useful Commands
- `aws iam get-user` - get AWS user that Terraform will use
- `terraform show -json | jq` - show current state
- `terraform plan` - refresh state and create execution plan
- `terraform apply` - apply/deploy changes
