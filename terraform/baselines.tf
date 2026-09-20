# The baseline module applied to each member account through its provider alias.

variable "budget_email" {
  type        = string
  description = "Where budget alerts go."
}

module "baseline_security" {
  source        = "./modules/account-baseline"
  providers     = { aws = aws.security }
  account_alias = "security"
  env           = "shared"
  github_repos  = []
  budget_usd    = var.budget_usd
  budget_email  = var.budget_email
}

module "baseline_dev" {
  source        = "./modules/account-baseline"
  providers     = { aws = aws.dev }
  account_alias = "dev"
  env           = "dev"
  github_repos  = lookup(var.github_repos, "dev", [])
  budget_usd    = var.budget_usd
  budget_email  = var.budget_email
}

module "baseline_prod" {
  source        = "./modules/account-baseline"
  providers     = { aws = aws.prod }
  account_alias = "prod"
  env           = "prod"
  github_repos  = lookup(var.github_repos, "prod", [])
  budget_usd    = var.budget_usd
  budget_email  = var.budget_email
}
