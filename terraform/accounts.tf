# Member accounts. Creating an account is effectively irreversible (a closed account
# lingers for 90 days and the email can't be reused), so `accounts` is data, not
# code: adding one is a one-line change, and `prevent_destroy` makes removing one
# a deliberate two-step.

resource "aws_organizations_account" "member" {
  for_each  = var.accounts
  name      = each.key
  email     = coalesce(each.value.email, "aws+${each.key}@${var.org_root_email_domain}")
  parent_id = local.ou_ids[each.value.ou]
  role_name = "OrganizationAccountAccessRole"
  # Closing an account through Terraform should never be a side effect of a refactor.
  close_on_deletion = false
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name] # cannot be changed after creation
  }
}

# One provider alias per member account, assuming the role Organizations creates.
provider "aws" {
  alias  = "security"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.member["security"].id}:role/OrganizationAccountAccessRole"
  }
}

provider "aws" {
  alias  = "dev"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.member["dev"].id}:role/OrganizationAccountAccessRole"
  }
}

provider "aws" {
  alias  = "prod"
  region = var.region
  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.member["prod"].id}:role/OrganizationAccountAccessRole"
  }
}
