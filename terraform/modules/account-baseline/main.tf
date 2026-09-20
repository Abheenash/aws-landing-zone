# Applied inside every member account: the things a fresh account should never
# be without. No VPCs, no workloads — those belong to the project repos, which
# deploy through the OIDC role created here.

terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

variable "account_alias" { type = string }
variable "env" { type = string }
variable "github_repos" {
  description = "owner/name repos whose main branch may assume the deploy role. Empty = no deploy role."
  type        = list(string)
  default     = []
}
variable "budget_usd" { type = number }
variable "budget_email" { type = string }

data "aws_caller_identity" "this" {}

# --- account-wide S3 public access block --------------------------------------
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- IAM password policy (console users, if any are ever created) -------------
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 16
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

# --- default EBS encryption ----------------------------------------------------
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# --- GitHub OIDC: keyless deploys, scoped to named repos and their main branch --
resource "aws_iam_openid_connect_provider" "github" {
  count           = length(var.github_repos) > 0 ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # GitHub's root CA; AWS validates against its own trust store since 2023
}

data "aws_iam_policy_document" "github_trust" {
  count = length(var.github_repos) > 0 ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only the main branch of the named repos — a PR from a fork, or any other
    # branch, cannot assume this role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for r in var.github_repos : "repo:${r}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "deploy" {
  count                = length(var.github_repos) > 0 ? 1 : 0
  name                 = "github-deploy-${var.env}"
  assume_role_policy   = data.aws_iam_policy_document.github_trust[0].json
  max_session_duration = 3600
  # The boundary caps what any future inline policy on this role can grant.
  permissions_boundary = aws_iam_policy.deploy_boundary[0].arn
}

# What a deploy pipeline may do in this account — and, via the boundary, the
# most it could ever do even if someone widens the attached policy later.
data "aws_iam_policy_document" "deploy_boundary" {
  statement {
    sid = "Infra"
    actions = [
      "ec2:*", "ecs:*", "ecr:*", "eks:*", "elasticloadbalancing:*", "autoscaling:*",
      "lambda:*", "apigateway:*", "dynamodb:*", "s3:*", "sqs:*", "sns:*", "events:*",
      "scheduler:*", "logs:*", "cloudwatch:*", "xray:*", "kms:*", "secretsmanager:*",
      "ssm:*", "states:*", "cloudfront:*", "route53:*", "acm:*", "wafv2:*",
      "application-autoscaling:*", "iam:Get*", "iam:List*", "iam:PassRole",
      "iam:CreateRole", "iam:DeleteRole", "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:TagRole", "iam:CreateServiceLinkedRole",
      "iam:CreateOpenIDConnectProvider", "iam:TagOpenIDConnectProvider",
    ]
    resources = ["*"]
  }
  statement {
    sid       = "NeverTouchTheGuardrails"
    effect    = "Deny"
    actions   = ["organizations:*", "cloudtrail:*", "config:*", "guardduty:*", "securityhub:*", "iam:CreateUser", "iam:CreateAccessKey", "iam:*PermissionsBoundary"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "deploy_boundary" {
  count  = length(var.github_repos) > 0 ? 1 : 0
  name   = "github-deploy-boundary-${var.env}"
  policy = data.aws_iam_policy_document.deploy_boundary.json
}

resource "aws_iam_role_policy" "deploy" {
  count  = length(var.github_repos) > 0 ? 1 : 0
  name   = "deploy"
  role   = aws_iam_role.deploy[0].id
  policy = data.aws_iam_policy_document.deploy_boundary.json
}

# --- budget: the cost guardrail every account gets --------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.account_alias}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}

output "deploy_role_arn" {
  value = length(var.github_repos) > 0 ? aws_iam_role.deploy[0].arn : null
}
output "account_id" {
  value = data.aws_caller_identity.this.account_id
}
