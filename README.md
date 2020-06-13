devops
===

Infrastructure-as-code using [Terraform](https://www.terraform.io/)

## Current Infrastructure
### ryanrishi.com
- S3
- CloudFront
- ACM for CloudFront distribution
- Route53 for DNS

## Useful Commands
- `aws iam get-user` - get AWS user that Terraform will use
- `terraform show` - show current state
- `terraform plan -var-file=staging.tfvars` - refresh state and create execution plan
- `terraform apply -var-file=staging.tfvars` - apply/deploy changes
- `terraform import aws_route53_record.ns ZONEID_example.com_NS` - import existing nameservers (since NS and SOA are automatically created)
- `terraform show -json | jq -r '.values.root_module.resources[] | select(.type == "aws_route_53_zone") | .values.name_servers'` - use `jq` to find something in state
- `terraform state show 'aws_cloudfront_distribution.ryanrishi-com'` - show state for a given resource
- `terraform workspace show` - show workspace (eg. `staging`, `production`)
- `terraform workspace select staging` - switch workspace
- `terraform state mv aws_cloudfront_distribution.ryanrishi-com aws_cloudfront_distribution.cloudfront_distribution` - move state (useful for renaming)
