# The organization and its OU tree.
#
#   Root
#   ├── Security        (log archive + audit tooling; nothing user-facing runs here)
#   ├── Workloads
#   │   ├── Dev
#   │   └── Prod
#   └── Sandbox         (experiments; the tightest region + service guardrails)
#
# SCPs are attached at the OU, never to individual accounts, so a new account
# inherits the guardrails the moment it lands in an OU.

resource "aws_organizations_organization" "org" {
  feature_set = "ALL" # SCPs need ALL; CONSOLIDATED_BILLING can't carry policies
  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",  # organization trail
    "config.amazonaws.com",      # org-wide Config aggregation (opt-in, costs money)
    "sso.amazonaws.com",         # IAM Identity Center
    "guardduty.amazonaws.com",   # delegated admin (opt-in)
    "securityhub.amazonaws.com", # delegated admin (opt-in)
  ]
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "dev" {
  name      = "Dev"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "prod" {
  name      = "Prod"
  parent_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "Sandbox"
  parent_id = aws_organizations_organization.org.roots[0].id
}

locals {
  ou_ids = {
    "security"       = aws_organizations_organizational_unit.security.id
    "workloads/dev"  = aws_organizations_organizational_unit.dev.id
    "workloads/prod" = aws_organizations_organizational_unit.prod.id
    "sandbox"        = aws_organizations_organizational_unit.sandbox.id
  }
}
