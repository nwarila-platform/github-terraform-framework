#% ========================================================================================== %#
#% = File: inventory.tftest.hcl                                                               %#
#% ------------------------------------------------------------------------------------------ %#
#% Credential-free inventory completeness and disclosure-boundary tests.                      %#
#% ========================================================================================== %#

mock_provider "github" {}
mock_provider "time" {}

variables {
  github_owner           = "test-owner"
  github_is_organization = true
  github_auth_mode       = "token"
  github_token           = "fake-token-for-unit-tests"
  github_app_auth        = null
  repo_yaml_path         = "tests/fixtures/good-minimal"
  repo_default_rules     = []

  security_baseline = {
    public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
  }
}

run "public_undeclared_repository_fails" {
  command = plan

  override_data {
    target = data.github_repositories.owner["test-owner"]
    values = {
      names = ["example-public-repo", "public-inventory-canary"]
    }
  }

  override_data {
    target = data.github_repositories.public["test-owner"]
    values = {
      names = ["example-public-repo", "public-inventory-canary"]
    }
  }

  expect_failures = [check.inventory_complete]

  assert {
    condition     = local.reportable_undeclared_repos == toset(["public-inventory-canary"])
    error_message = "a public undeclared repository must remain reportable by name"
  }

  assert {
    condition     = local.redacted_undeclared_repo_count == 0
    error_message = "a public undeclared repository must not increment the redacted count"
  }
}

run "non_public_undeclared_repository_is_redacted" {
  command = plan

  override_data {
    target = data.github_repositories.owner["test-owner"]
    values = {
      names = ["example-public-repo", "owner-only-sensitive-sentinel-7f3"]
    }
  }

  override_data {
    target = data.github_repositories.public["test-owner"]
    values = {
      names = ["example-public-repo"]
    }
  }

  expect_failures = [check.inventory_complete]

  assert {
    condition     = length(local.reportable_undeclared_repos) == 0
    error_message = "an owner-only undeclared repository must not be reportable by name"
  }

  assert {
    condition     = local.redacted_undeclared_repo_count == 1
    error_message = "an owner-only undeclared repository must increment only the redacted count"
  }
}

run "complete_organization_inventory_passes" {
  command = plan

  override_data {
    target = data.github_repositories.owner["test-owner"]
    values = {
      names = ["example-public-repo"]
    }
  }

  override_data {
    target = data.github_repositories.public["test-owner"]
    values = {
      names = ["example-public-repo"]
    }
  }

  assert {
    condition     = length(local.undeclared_repos) == 0
    error_message = "a complete organization inventory must pass the advisory check"
  }

  assert {
    condition     = strcontains(data.github_repositories.owner["test-owner"].query, "fork:true")
    error_message = "the owner inventory query must include forks"
  }

  assert {
    condition     = strcontains(data.github_repositories.public["test-owner"].query, "fork:true")
    error_message = "the public inventory query must include forks"
  }
}

run "personal_mode_skips_inventory_searches" {
  command = plan

  variables {
    github_is_organization = false
  }

  assert {
    condition     = length(data.github_repositories.owner) == 0
    error_message = "personal mode must not run the owner inventory search"
  }

  assert {
    condition     = length(data.github_repositories.public) == 0
    error_message = "personal mode must not run the public inventory search"
  }
}
