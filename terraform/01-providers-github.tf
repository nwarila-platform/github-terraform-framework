#% =========================================================================================== %#
#% = File: 01-providers-github.tf                                | Category: Providers (00-09) %#
#% ----- [ Description ] --------------------------------------------------------------------- %#
#% GitHub provider configuration. Supports two authentication modes, selected by                %#
#%   var.github_auth_mode:                                                                      %#
#%     - "app"   — GitHub App installation (preferred for enterprise automation)                %#
#%     - "token" — classic or fine-grained PAT (break-glass / bootstrap only)                  %#
#% Exactly one of var.github_token or var.github_app_auth must be non-null. Enforcement lives   %#
#%   in terraform_data.framework_validation via local.global_validation_errors.                 %#
#% =========================================================================================== %#

provider "github" {
  owner = var.github_owner
  token = var.github_auth_mode == "token" ? var.github_token : null

  dynamic "app_auth" {
    for_each = var.github_auth_mode == "app" && var.github_app_auth != null ? [var.github_app_auth] : []
    content {
      id              = app_auth.value.id
      installation_id = app_auth.value.installation_id
      pem_file        = app_auth.value.pem_file
    }
  }
}
