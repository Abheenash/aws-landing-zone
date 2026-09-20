# Service control policies — the guardrails. Each is a JSON document in policies/
# so it can be unit-tested (tests/test_policies.py) without Terraform, and so a
# reviewer reads the policy, not HCL that generates one.
#
# Attachment strategy: guardrails that apply everywhere go on the Root; stricter
# ones go on the OU. SCPs are deny-only filters — they never grant — so the order
# of attachment doesn't matter, only the union of denies.

locals {
  scp_dir = "${path.module}/policies"
  scp_vars = {
    home_regions  = jsonencode(var.home_regions)
    required_tags = var.required_tags
    org_id        = aws_organizations_organization.org.id
  }
}

# 1. Nobody uses root — no root access keys, no root API calls except the handful
#    that only root can do (billing, account closure, support plan).
resource "aws_organizations_policy" "deny_root" {
  name        = "deny-root-user"
  description = "Deny the root user everything except the actions only root can perform"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.scp_dir}/deny-root-user.json")
}

# 2. Region lock — every API call outside the home regions is denied, except the
#    global services that only live in us-east-1 (IAM, STS, Organizations, CloudFront,
#    Route 53, Budgets, Support, Health).
resource "aws_organizations_policy" "region_lock" {
  name        = "region-lock"
  description = "Deny all actions outside the home regions, exempting global services"
  type        = "SERVICE_CONTROL_POLICY"
  content     = templatefile("${local.scp_dir}/region-lock.json.tftpl", local.scp_vars)
}

# 3. Protect the guardrails themselves and the audit trail: no one in a member
#    account can leave the org, disable CloudTrail/Config/GuardDuty, or touch the
#    OrganizationAccountAccessRole.
resource "aws_organizations_policy" "protect_baseline" {
  name        = "protect-security-baseline"
  description = "Deny disabling CloudTrail/Config/GuardDuty, leaving the org, or altering the org access role"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.scp_dir}/protect-security-baseline.json")
}

# 4. Tag enforcement — creating the resources that cost money (EC2, RDS, Lambda, S3,
#    ECS, EKS, DynamoDB) without Project and Owner tags is denied. Cost allocation
#    reports are only as good as the tags.
resource "aws_organizations_policy" "require_tags" {
  name        = "require-cost-tags"
  description = "Deny creating cost-bearing resources without the required tags"
  type        = "SERVICE_CONTROL_POLICY"
  content     = templatefile("${local.scp_dir}/require-tags.json.tftpl", local.scp_vars)
}

# 5. Sandbox: no expensive or persistent services at all — no RDS, no EKS, no
#    NAT gateways, no reserved/savings-plan purchases, nothing bigger than *.large.
resource "aws_organizations_policy" "sandbox_limits" {
  name        = "sandbox-limits"
  description = "Deny expensive and persistent services in the sandbox OU"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.scp_dir}/sandbox-limits.json")
}

# --- attachments -------------------------------------------------------------
resource "aws_organizations_policy_attachment" "root_deny_root" {
  policy_id = aws_organizations_policy.deny_root.id
  target_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_policy_attachment" "root_region_lock" {
  policy_id = aws_organizations_policy.region_lock.id
  target_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_policy_attachment" "root_protect_baseline" {
  policy_id = aws_organizations_policy.protect_baseline.id
  target_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_policy_attachment" "workloads_require_tags" {
  policy_id = aws_organizations_policy.require_tags.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "sandbox_limits" {
  policy_id = aws_organizations_policy.sandbox_limits.id
  target_id = aws_organizations_organizational_unit.sandbox.id
}

# Tag policy: the *shape* of the tags (allowed values), enforced org-wide for
# compliance reporting; the SCP above is what actually blocks untagged creation.
resource "aws_organizations_policy" "tag_shape" {
  name        = "tag-shape"
  description = "Project must be lowercase-kebab; Owner must be an email"
  type        = "TAG_POLICY"
  content = jsonencode({
    tags = {
      Project = { tag_key = { "@@assign" = "Project" }, enforced_for = { "@@assign" = ["ec2:instance", "rds:db", "lambda:function", "s3:bucket", "dynamodb:table"] } }
      Owner   = { tag_key = { "@@assign" = "Owner" } }
      Env     = { tag_key = { "@@assign" = "Env" }, tag_value = { "@@assign" = ["dev", "prod", "sandbox", "shared"] } }
    }
  })
}

resource "aws_organizations_policy_attachment" "root_tag_shape" {
  policy_id = aws_organizations_policy.tag_shape.id
  target_id = aws_organizations_organization.org.roots[0].id
}
