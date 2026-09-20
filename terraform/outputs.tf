output "organization_id" {
  value = aws_organizations_organization.org.id
}

output "account_ids" {
  value = { for k, a in aws_organizations_account.member : k => a.id }
}

output "deploy_roles" {
  description = "Paste into each repo's AWS_ROLE_ARN variable."
  value = {
    dev  = module.baseline_dev.deploy_role_arn
    prod = module.baseline_prod.deploy_role_arn
  }
}

output "audit_bucket" {
  value = aws_s3_bucket.audit.id
}
