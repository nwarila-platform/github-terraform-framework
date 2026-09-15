# Provider-gap declarations are output-only desired state. These tests cover
# the closed YAML grammar, normalization, enums, private visibility, personal
# owner rules, and exact planned output representation.

mock_provider "github" {}
mock_provider "time" {}

variables {
  github_owner           = "test-owner"
  github_is_organization = false
  github_auth_mode       = "token"
  github_token           = "fake-token-for-unit-tests"
  github_app_auth        = null

  security_baseline = {
    public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
  }
}

run "repository_gap_normalization_has_exact_projection" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-provider-gaps"
  }

  assert {
    condition = jsonencode(output.provider_gap_desired_state) == jsonencode({
      schema_version             = 1
      github_owner               = "test-owner"
      github_is_organization     = false
      organization_provider_gaps = null
      repositories = {
        absent = {
          name          = "absent"
          visibility    = "public"
          archived      = false
          provider_gaps = null
        }
        archived = {
          name       = "archived"
          visibility = "public"
          archived   = true
          provider_gaps = {
            fork_pr_contributor_approval = "all_external_contributors"
          }
        }
        empty = {
          name          = "empty"
          visibility    = "public"
          archived      = false
          provider_gaps = null
        }
        explicit = {
          name       = "explicit"
          visibility = "public"
          archived   = false
          provider_gaps = {
            fork_pr_contributor_approval = "first_time_contributors"
          }
        }
        member-null = {
          name          = "member-null"
          visibility    = "public"
          archived      = false
          provider_gaps = null
        }
        null-block = {
          name          = "null-block"
          visibility    = "public"
          archived      = false
          provider_gaps = null
        }
        private-absent = {
          name          = "private-absent"
          visibility    = "private"
          archived      = false
          provider_gaps = null
        }
      }
    })
    error_message = "provider-gap output must use the exact closed projection and collapse absent/empty/null repository declarations to null"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "valid provider-gap normalization fixture must plan cleanly"
  }
}

run "organization_optional_members_materialize_as_null" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-empty"
    github_is_organization = true
    provider_gaps          = {}
  }

  assert {
    condition = jsonencode(output.provider_gap_desired_state.organization_provider_gaps) == jsonencode({
      fork_pr_contributor_approval = null
      code_security_configuration  = null
    })
    error_message = "omitted organization optional members must materialize as both exact null-valued keys"
  }
}

run "organization_projection_preserves_closed_code_security_shape" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-empty"
    github_is_organization = true
    provider_gaps = {
      fork_pr_contributor_approval = "all_external_contributors"
      code_security_configuration = {
        id          = 7
        enforcement = "enforced"
        defaults    = ["dependency_graph"]
        status      = "configured"
      }
    }
  }

  assert {
    condition = jsonencode(output.provider_gap_desired_state.organization_provider_gaps) == jsonencode({
      fork_pr_contributor_approval = "all_external_contributors"
      code_security_configuration = {
        id          = 7
        enforcement = "enforced"
        defaults    = ["dependency_graph"]
        status      = "configured"
      }
    })
    error_message = "organization projection must preserve the exact closed provider-gap object"
  }
}

run "rejects_unknown_provider_gap_key" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-provider-gap-key"
  }

  expect_failures = [terraform_data.framework_validation]
}

run "rejects_repository_policy_outside_enum" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-provider-gap-enum"
  }

  expect_failures = [terraform_data.framework_validation]
}

run "rejects_private_repository_declaration" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-private-provider-gap"
  }

  expect_failures = [terraform_data.framework_validation]
}

run "rejects_personal_organization_policy" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-empty"
    provider_gaps = {
      fork_pr_contributor_approval = "all_external_contributors"
    }
  }

  expect_failures = [terraform_data.framework_validation]
}

run "rejects_organization_policy_outside_enum" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-empty"
    github_is_organization = true
    provider_gaps = {
      fork_pr_contributor_approval = "not-a-policy"
    }
  }

  expect_failures = [terraform_data.framework_validation]
}
