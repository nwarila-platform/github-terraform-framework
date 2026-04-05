#% ========================================================================================== %#
#% = File: providers.tf                                         | Category: Providers (00-09) %#
#% ----- [ Description ] -------------------------------------------------------------------- %#
#% ========================================================================================== %#
terraform {

  // Declare minimum Terraform version.
  required_version = "1.14.3"

  backend "s3" {
    encrypt                     = true
    insecure                    = false
    skip_credentials_validation = false
    use_fips_endpoint           = true
    use_lockfile                = true
  }

  required_providers {

    github = {
      source  = "integrations/github"
      version = "6.10.2"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "6.28.0"
    }

  }

}
