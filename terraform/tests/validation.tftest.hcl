#% ========================================================================================== %#
#% = File: validation.tftest.hcl                                                               %#
#% ------------------------------------------------------------------------------------------ %#
#% Regression suite for the framework validation layer. Each run block points the framework   %#
#%   at a fixture directory under tests/fixtures/<case> by overriding var.repo_yaml_path.     %#
#%                                                                                             %#
#% Positive runs assert that output.validation_errors is empty.                                %#
#% Negative runs use expect_failures to assert terraform_data.framework_validation fails.     %#
#%                                                                                             %#
#% mock_provider blocks let the plan evaluate without real provider credentials or API calls.  %#
#%   terraform_data.framework_validation still evaluates its precondition before any mocked   %#
#%   resource is created, so negative cases fail fast at the validation gate.                 %#
#% ========================================================================================== %#

mock_provider "github" {}
mock_provider "aws" {}
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

#region ------ [ Positive cases ] ------------------------------------------------------------ #

run "good_minimal_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-minimal"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "good-minimal fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }
}

#endregion --- [ Positive cases ] ------------------------------------------------------------ #

#region ------ [ Negative cases ] ------------------------------------------------------------ #

run "rejects_unknown_top_level_key" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-unknown-top-key"
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_unknown_nested_key" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-unknown-nested-key"
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_allow_forking" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-allow-forking"
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_duplicate_repo_keys" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-duplicate-keys"
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_unsupported_push_ruleset" {
  command = plan

  variables {
    repo_yaml_path                = "tests/fixtures/bad-push-ruleset"
    github_supports_push_rulesets = false
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_code_scanning_tool_typo" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-code-scanning-tool-typo"
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_multiple_nested_typos_in_one_repo" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-multi-nested-typos"
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_secrets_written_as_map" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-secrets-as-map"
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

#endregion --- [ Negative cases ] ------------------------------------------------------------ #

#region ------ [ Auth config cases ] ---------------------------------------------------------- #

run "rejects_token_mode_missing_token" {
  command = plan

  variables {
    repo_yaml_path   = "tests/fixtures/good-minimal"
    github_auth_mode = "token"
    github_token     = null
    github_app_auth  = null
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_app_mode_missing_app_auth" {
  command = plan

  variables {
    repo_yaml_path   = "tests/fixtures/good-minimal"
    github_auth_mode = "app"
    github_token     = null
    github_app_auth  = null
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_token_mode_with_app_auth_also_set" {
  command = plan

  variables {
    repo_yaml_path   = "tests/fixtures/good-minimal"
    github_auth_mode = "token"
    github_token     = "fake-token"
    github_app_auth = {
      id              = "12345"
      installation_id = "67890"
      pem_file        = "fake-pem"
    }
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "rejects_app_mode_with_token_also_set" {
  command = plan

  variables {
    repo_yaml_path   = "tests/fixtures/good-minimal"
    github_auth_mode = "app"
    github_token     = "fake-token"
    github_app_auth = {
      id              = "12345"
      installation_id = "67890"
      pem_file        = "fake-pem"
    }
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "valid_app_auth_plans_clean" {
  command = plan

  variables {
    repo_yaml_path   = "tests/fixtures/good-minimal"
    github_auth_mode = "app"
    github_token     = null
    github_app_auth = {
      id              = "12345"
      installation_id = "67890"
      pem_file        = "fake-pem"
    }
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "valid app auth config must plan clean. errors: ${join(" | ", output.validation_errors)}"
  }
}

#endregion --- [ Auth config cases ] ---------------------------------------------------------- #

#region ------ [ Security baseline cases ] ---------------------------------------------------- #

run "strict_mode_fails_on_capability_gap" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-minimal"
    security_baseline_mode = "strict"

    # Baseline demands GHAS on public; capabilities say false → strict
    # must fail. Explicit declaration of the full matrix because the
    # variables are Packer-coherence style (no optional()).
    github_security_capabilities = {
      public = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      private = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      internal = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
    }

    security_baseline = {
      public = {
        advanced_security                     = true
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      private = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      internal = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
    }
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "compatibility_mode_tolerates_capability_gap" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-minimal"
    security_baseline_mode = "compatibility"

    github_security_capabilities = {
      public = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      private = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      internal = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
    }

    security_baseline = {
      public = {
        advanced_security                     = true
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      private = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      internal = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
    }
  }

  expect_failures = [
    check.security_baseline_preview,
  ]

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "compatibility mode must not raise the capability gap as a hard error. Got: ${join(" | ", output.validation_errors)}"
  }

  assert {
    condition     = length(output.security_capability_gap_preview) > 0
    error_message = "compatibility mode must still populate the preview list so operators can see the gap before flipping to strict."
  }
}

#endregion --- [ Security baseline cases ] ---------------------------------------------------- #

#region ------ [ Push ruleset matrix (6 conditions) ] ---------------------------------------- #

# The 6 conditions: target=push × visibility(public|private|internal) × supports(true|false).
# - supports=false always fails (no visibility is eligible)
# - supports=true passes only for private/internal; public still fails because
#   GitHub's push rulesets are not available on public repos regardless of plan.
# Existing coverage (rejects_unsupported_push_ruleset + validation of good-push-ruleset
# in normalization.tftest.hcl) covers public+false and private+true. These runs
# fill in the remaining 4 cells.

run "push_ruleset_public_supports_true_still_fails" {
  command = plan

  variables {
    repo_yaml_path                = "tests/fixtures/bad-push-ruleset"
    github_supports_push_rulesets = true
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "push_ruleset_private_supports_false_fails" {
  command = plan

  variables {
    repo_yaml_path                = "tests/fixtures/good-push-ruleset"
    github_supports_push_rulesets = false
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

run "push_ruleset_internal_supports_true_passes" {
  command = plan

  variables {
    repo_yaml_path                = "tests/fixtures/good-internal-push-ruleset"
    github_supports_push_rulesets = true
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "internal+supports=true must pass: ${join(" | ", output.validation_errors)}"
  }
}

run "push_ruleset_internal_supports_false_fails" {
  command = plan

  variables {
    repo_yaml_path                = "tests/fixtures/good-internal-push-ruleset"
    github_supports_push_rulesets = false
  }

  expect_failures = [
    terraform_data.framework_validation,
  ]
}

#endregion --- [ Push ruleset matrix (6 conditions) ] ---------------------------------------- #

#region ------ [ Variable validation (regex / enum) ] ---------------------------------------- #

# These runs test the `validation {}` blocks on variable declarations. The
# expected failure address is the variable itself — terraform test reports
# variable validation failures as var.<name>.

run "rejects_invalid_github_owner_regex" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-minimal"
    github_owner   = "-invalid-starts-with-hyphen"
  }

  expect_failures = [
    var.github_owner,
  ]
}

run "rejects_invalid_auth_mode_enum" {
  command = plan

  variables {
    repo_yaml_path   = "tests/fixtures/good-minimal"
    github_auth_mode = "oauth"
  }

  expect_failures = [
    var.github_auth_mode,
  ]
}

run "rejects_invalid_baseline_mode_enum" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-minimal"
    security_baseline_mode = "paranoid"
  }

  expect_failures = [
    var.security_baseline_mode,
  ]
}

#endregion --- [ Variable validation (regex / enum) ] ---------------------------------------- #
