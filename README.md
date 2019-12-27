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
- `terraform import aws_route53_record.ns ZONEID_example.com_NS` - import existing nameservers (since NS and SOA are automatically created)
- `terraform show -json | jq -r '.values.root_module.resources[] | select(.type == "aws_route_53_zone") | .values.name_servers'` - use `jq` to find something in state
