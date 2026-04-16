#% ========================================================================================== %#
#% = File: preconditions.tftest.hcl                                                            %#
#% ------------------------------------------------------------------------------------------ %#
#% Regression suite for per-resource lifecycle.precondition blocks. Each run block points the  %#
#%   framework at a fixture that passes global validation but violates exactly one per-        %#
#%   resource precondition, so expect_failures pinpoints the specific resource address.        %#
#%                                                                                             %#
#% Why this layer matters: per-resource preconditions exist to surface errors at the specific  %#
#%   github_repository.repo["<name>"] / github_repository_ruleset.branch["<key>"] address so   %#
#%   operators know exactly which repo/rule is broken. Tests must therefore assert failures    %#
#%   at those addresses, not at terraform_data.framework_validation.                           %#
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

#region ------ [ github_repository.repo preconditions ] -------------------------------------- #

run "rejects_invalid_visibility_enum" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-visibility-enum"
  }

  expect_failures = [
    github_repository.repo["bad-visibility-repo"],
  ]
}

run "rejects_public_repo_without_description" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-public-no-description"
  }

  expect_failures = [
    github_repository.repo["bad-public-no-description-repo"],
  ]
}

#endregion --- [ github_repository.repo preconditions ] -------------------------------------- #

#region ------ [ github_repository_ruleset.branch preconditions ] ---------------------------- #

run "rejects_invalid_ruleset_enforcement" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-ruleset-enforcement"
  }

  expect_failures = [
    github_repository_ruleset.branch["bad-ruleset-enforcement-repo-rules-0"],
  ]
}

run "rejects_org_mode_codeowners_required_but_missing" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/bad-ruleset-codeowners-missing-org"
    github_is_organization = true
  }

  expect_failures = [
    github_repository_ruleset.branch["bad-codeowners-org-repo-rules-0"],
  ]
}

#endregion --- [ github_repository_ruleset.branch preconditions ] ---------------------------- #

#region ------ [ github_repository_environment.environment preconditions ] ------------------- #

run "rejects_env_wait_timer_out_of_range" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-env-wait-timer"
  }

  expect_failures = [
    github_repository_environment.environment["bad-env-wait-timer-repo::production"],
  ]
}

run "rejects_env_branch_policy_mutually_exclusive" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-env-branch-policy-both"
  }

  expect_failures = [
    github_repository_environment.environment["bad-env-branch-policy-both-repo::production"],
  ]
}

#endregion --- [ github_repository_environment.environment preconditions ] ------------------- #

#region ------ [ github_actions_repository_permissions.actions preconditions ] --------------- #

run "rejects_actions_allowed_actions_enum" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-actions-enum"
  }

  expect_failures = [
    github_actions_repository_permissions.actions["bad-actions-enum-repo"],
  ]
}

run "rejects_actions_selected_without_config" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/bad-actions-selected-no-config"
  }

  expect_failures = [
    github_actions_repository_permissions.actions["bad-actions-selected-no-config-repo"],
  ]
}

#endregion --- [ github_actions_repository_permissions.actions preconditions ] --------------- #
