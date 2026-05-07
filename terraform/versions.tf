terraform {
  # Pin Terraform exactly per org ADR 0005.
  required_version = "= 1.15.1"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "= 6.10.2"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "= 6.28.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "= 0.12.1"
    }
  }
}
