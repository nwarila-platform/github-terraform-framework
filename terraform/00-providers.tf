#% ========================================================================================== %#
#% = File: 00-providers.tf                                      | Category: Providers (00-09) %#
#% ----- [ Description ] -------------------------------------------------------------------- %#
#% Backend declaration. Terraform required_version and required_providers live in versions.tf
#% per the golden template contract.
#% ========================================================================================== %#
terraform {
  backend "s3" {
    encrypt                     = true
    insecure                    = false
    skip_credentials_validation = false
    use_fips_endpoint           = true
    use_lockfile                = true
  }
}
