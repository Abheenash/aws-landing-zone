variable "region" {
  type    = string
  default = "us-east-1"
}

variable "home_regions" {
  description = "Regions workloads may use. Every other region is denied by SCP (keeps the blast radius and the bill in one place)."
  type        = list(string)
  default     = ["us-east-1", "us-west-2"]
}

variable "org_root_email_domain" {
  description = "Member accounts get <alias>@<domain> addresses (use a plus-addressed or catch-all mailbox)."
  type        = string
}

variable "accounts" {
  description = "Member accounts to create, keyed by alias, with the OU they belong in."
  type = map(object({
    ou    = string # security | workloads/dev | workloads/prod | sandbox
    email = optional(string)
  }))
  default = {
    security = { ou = "security" }
    dev      = { ou = "workloads/dev" }
    prod     = { ou = "workloads/prod" }
    sandbox  = { ou = "sandbox" }
  }
}

variable "github_repos" {
  description = "GitHub repos (owner/name) allowed to assume the deploy role in each workload account, by account alias."
  type        = map(list(string))
  default = {
    dev  = ["Abheenash/secure-container-pipeline", "Abheenash/aws-eks-platform", "Abheenash/serverless-file-share"]
    prod = ["Abheenash/serverless-file-share"]
  }
}

variable "required_tags" {
  description = "Tags every taggable resource must carry; creation without them is denied by SCP."
  type        = list(string)
  default     = ["Project", "Owner"]
}

variable "budget_usd" {
  description = "Monthly budget per workload account; alerts at 80% and 100% of forecast."
  type        = number
  default     = 20
}
