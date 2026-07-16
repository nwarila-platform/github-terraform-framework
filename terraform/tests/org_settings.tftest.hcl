#% ========================================================================================== %#
#% = File: org_settings.tftest.hcl                                                            %#
#% ------------------------------------------------------------------------------------------ %#
#% Organization settings opt-in, validation, safe-default, and full-attribute contract tests. %#
#% ========================================================================================== %#

mock_provider "github" {}
mock_provider "time" {}

variables {
  github_owner           = "test-owner"
  github_is_organization = false
  github_auth_mode       = "token"
  github_token           = "fake-token-for-unit-tests"
  github_app_auth        = null
  repo_yaml_path         = "tests/fixtures/good-minimal"

  # Org-setting tests do not exercise repository rulesets. Keep the shared
  # minimal fixture from inheriting the default code-owner-review ruleset,
  # while this test supplies neither per-repo codeowners nor a usable global default.
  repo_default_rules = []

  # Restated matrices keep repository security checks out of these org-setting tests.
  github_security_capabilities = {
    public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
  }

  security_baseline = {
    public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
  }
}

#region ------ [ T1 | Defaults leave org settings unmanaged ] -------------------------------- #

run "default_org_settings_are_unmanaged" {
  command = plan

  assert {
    condition     = length(github_organization_settings.org) == 0
    error_message = "pure org-setting defaults must not manage organization settings"
  }
}

#endregion --- [ T1 | Defaults leave org settings unmanaged ] -------------------------------- #

#region ------ [ T2 | Safe defaults and full attribute contract ] ---------------------------- #

run "minimal_opt_in_plans_every_safe_default" {
  command = plan

  variables {
    github_is_organization = true
    org_settings           = { name = "Test Organization" }
    org_billing_email      = "billing@example.invalid"
  }

  assert {
    condition     = length(github_organization_settings.org) == 1
    error_message = "an organization opt-in must plan exactly one organization settings resource"
  }

  assert {
    condition = (
      github_organization_settings.org[0].name == "Test Organization" &&
      github_organization_settings.org[0].description == "" &&
      github_organization_settings.org[0].company == "" &&
      github_organization_settings.org[0].blog == "" &&
      github_organization_settings.org[0].email == "" &&
      github_organization_settings.org[0].location == "" &&
      github_organization_settings.org[0].twitter_username == "" &&
      github_organization_settings.org[0].default_repository_permission == "read" &&
      github_organization_settings.org[0].members_can_create_repositories == false &&
      github_organization_settings.org[0].members_can_create_public_repositories == false &&
      github_organization_settings.org[0].members_can_create_private_repositories == false &&
      github_organization_settings.org[0].members_can_create_internal_repositories == false &&
      github_organization_settings.org[0].members_can_create_pages == false &&
      github_organization_settings.org[0].members_can_create_public_pages == false &&
      github_organization_settings.org[0].members_can_create_private_pages == false &&
      github_organization_settings.org[0].members_can_fork_private_repositories == false &&
      github_organization_settings.org[0].has_organization_projects == false &&
      github_organization_settings.org[0].has_repository_projects == false &&
      github_organization_settings.org[0].web_commit_signoff_required == true &&
      github_organization_settings.org[0].advanced_security_enabled_for_new_repositories == false &&
      github_organization_settings.org[0].secret_scanning_enabled_for_new_repositories == false &&
      github_organization_settings.org[0].secret_scanning_push_protection_enabled_for_new_repositories == false &&
      github_organization_settings.org[0].dependabot_alerts_enabled_for_new_repositories == false &&
      github_organization_settings.org[0].dependabot_security_updates_enabled_for_new_repositories == false &&
      github_organization_settings.org[0].dependency_graph_enabled_for_new_repositories == false
    )
    error_message = "minimal opt-in must explicitly plan all 25 non-sensitive managed attributes at safe defaults"
  }
}

#endregion --- [ T2 | Safe defaults and full attribute contract ] ---------------------------- #

#region ------ [ T2b | Non-default anti-omission contract ] ---------------------------------- #

run "non_default_opt_in_plans_every_managed_attribute" {
  command = plan

  variables {
    github_is_organization = true
    org_billing_email      = "billing@example.invalid"
    org_settings = {
      name                                     = "x-name"
      description                              = "x-description"
      company                                  = "x-company"
      blog                                     = "x-blog"
      email                                    = "x-email"
      location                                 = "x-location"
      twitter_username                         = "x-twitter"
      default_repository_permission            = "write"
      members_can_create_repositories          = true
      members_can_create_public_repositories   = true
      members_can_create_private_repositories  = true
      members_can_create_internal_repositories = true
      members_can_create_pages                 = true
      members_can_create_public_pages          = true
      members_can_create_private_pages         = true
      members_can_fork_private_repositories    = true
      has_organization_projects                = true
      has_repository_projects                  = true
      web_commit_signoff_required              = true
      security_defaults_for_new_repositories = {
        advanced_security               = true
        secret_scanning                 = true
        secret_scanning_push_protection = true
        dependabot_alerts               = true
        dependabot_security_updates     = true
        dependency_graph                = true
      }
    }
  }

  assert {
    condition = (
      github_organization_settings.org[0].name == "x-name" &&
      github_organization_settings.org[0].description == "x-description" &&
      github_organization_settings.org[0].company == "x-company" &&
      github_organization_settings.org[0].blog == "x-blog" &&
      github_organization_settings.org[0].email == "x-email" &&
      github_organization_settings.org[0].location == "x-location" &&
      github_organization_settings.org[0].twitter_username == "x-twitter" &&
      github_organization_settings.org[0].default_repository_permission == "write" &&
      github_organization_settings.org[0].members_can_create_repositories == true &&
      github_organization_settings.org[0].members_can_create_public_repositories == true &&
      github_organization_settings.org[0].members_can_create_private_repositories == true &&
      github_organization_settings.org[0].members_can_create_internal_repositories == true &&
      github_organization_settings.org[0].members_can_create_pages == true &&
      github_organization_settings.org[0].members_can_create_public_pages == true &&
      github_organization_settings.org[0].members_can_create_private_pages == true &&
      github_organization_settings.org[0].members_can_fork_private_repositories == true &&
      github_organization_settings.org[0].has_organization_projects == true &&
      github_organization_settings.org[0].has_repository_projects == true &&
      github_organization_settings.org[0].web_commit_signoff_required == true &&
      github_organization_settings.org[0].advanced_security_enabled_for_new_repositories == true &&
      github_organization_settings.org[0].secret_scanning_enabled_for_new_repositories == true &&
      github_organization_settings.org[0].secret_scanning_push_protection_enabled_for_new_repositories == true &&
      github_organization_settings.org[0].dependabot_alerts_enabled_for_new_repositories == true &&
      github_organization_settings.org[0].dependabot_security_updates_enabled_for_new_repositories == true &&
      github_organization_settings.org[0].dependency_graph_enabled_for_new_repositories == true
    )
    error_message = "non-default opt-in must propagate every one of the 25 non-sensitive managed attributes"
  }
}

#endregion --- [ T2b | Non-default anti-omission contract ] ---------------------------------- #

#region ------ [ Validation failures ] ------------------------------------------------------- #

run "personal_account_rejects_org_settings" {
  command = plan

  variables {
    org_settings      = { name = "Test Organization" }
    org_billing_email = "billing@example.invalid"
  }

  expect_failures = [terraform_data.framework_validation]
}

run "managed_org_requires_billing_email" {
  command = plan

  variables {
    github_is_organization = true
    org_settings           = { name = "Test Organization" }
  }

  expect_failures = [terraform_data.framework_validation]
}

run "managed_org_rejects_whitespace_billing_email" {
  command = plan

  variables {
    github_is_organization = true
    org_settings           = { name = "Test Organization" }
    org_billing_email      = "   "
  }

  expect_failures = [terraform_data.framework_validation]
}

run "managed_org_rejects_whitespace_name" {
  command = plan

  variables {
    github_is_organization = true
    org_settings           = { name = "  " }
    org_billing_email      = "billing@example.invalid"
  }

  expect_failures = [terraform_data.framework_validation]
}

run "unmanaged_org_rejects_dangling_billing_email" {
  command = plan

  variables {
    org_billing_email = "billing@example.invalid"
  }

  expect_failures = [terraform_data.framework_validation]
}

#endregion --- [ Validation failures ] ------------------------------------------------------- #

#region ------ [ T6 | Explicit paid opt-in ] ------------------------------------------------- #

run "advanced_security_explicit_opt_in_plans_true" {
  command = plan

  variables {
    github_is_organization = true
    org_settings = {
      name = "Test Organization"
      security_defaults_for_new_repositories = {
        advanced_security = true
      }
    }
    org_billing_email = "billing@example.invalid"
  }

  assert {
    condition     = github_organization_settings.org[0].advanced_security_enabled_for_new_repositories == true
    error_message = "advanced security true must plan through as an explicit paid-feature opt-in"
  }
}

#endregion --- [ T6 | Explicit paid opt-in ] ------------------------------------------------- #

#region ------ [ T7 | Permission enum validation ] ------------------------------------------- #

run "invalid_default_repository_permission_fails" {
  command = plan

  variables {
    github_is_organization = true
    org_settings = {
      name                          = "Test Organization"
      default_repository_permission = "owner"
    }
    org_billing_email = "billing@example.invalid"
  }

  expect_failures = [var.org_settings]
}

#endregion --- [ T7 | Permission enum validation ] ------------------------------------------- #

#region ------ [ T8 | Empty profile semantics ] --------------------------------------------- #

run "omitted_description_plans_empty" {
  command = plan

  variables {
    github_is_organization = true
    org_settings           = { name = "Test Organization" }
    org_billing_email      = "billing@example.invalid"
  }

  assert {
    condition     = github_organization_settings.org[0].description == ""
    error_message = "an omitted profile description must plan as an explicit empty string"
  }
}

#endregion --- [ T8 | Empty profile semantics ] --------------------------------------------- #
