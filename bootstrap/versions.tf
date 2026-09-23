terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  # Deliberately NOT configured. This is the chicken-and-egg root: the thing that
  # creates the state backend cannot itself live in the state backend. Its state
  # is local, it is applied once, and it is the only Terraform in my projects that
  # is allowed to be that way.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "aws-landing-zone"
      Component = "tfstate-backend"
      ManagedBy = "terraform"
    }
  }
}
