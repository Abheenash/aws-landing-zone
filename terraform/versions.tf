terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# The management account. Member-account resources use provider aliases that
# assume OrganizationAccountAccessRole into each account (see accounts.tf).
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "aws-landing-zone", ManagedBy = "terraform" }
  }
}
