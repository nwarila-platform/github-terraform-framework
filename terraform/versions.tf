terraform {
  # Pin Terraform exactly per template ADR 0001.
  required_version = "= 1.15.4"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "= 6.12.1"
    }

    time = {
      source  = "hashicorp/time"
      version = "= 0.12.1"
    }
  }
}
