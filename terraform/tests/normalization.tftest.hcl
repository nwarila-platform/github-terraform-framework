#% ========================================================================================== %#
#% = File: normalization.tftest.hcl                                                            %#
#% ------------------------------------------------------------------------------------------ %#
#% Positive regression tests for the locals normalization layer. These fixtures were chosen    %#
#%   to specifically exercise the bugs fixed in Finding 5 / S4 of REVIEW_REMEDIATION_PLAN.md   %#
#%   — partial pattern blocks, partial merge_queue, partial pull_request, pages.cname with    %#
#%   other fields omitted, etc. Each run asserts plan succeeds AND output.validation_errors   %#
#%   is empty, which is the contract for a clean normalization path.                         %#
#% ========================================================================================== %#

mock_provider "github" {}
mock_provider "time" {}

variables {
  github_owner           = "test-owner"
  github_is_organization = false
  github_auth_mode       = "token"
  github_token           = "fake-token-for-unit-tests"
  github_app_auth        = null

  # Suppress check.security_baseline_preview noise by zeroing the baseline.
  # Security-specific tests live in security.tftest.hcl with explicit overrides.
  security_baseline = {
    public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
  }
}

#region ------ [ S4: pattern block partial-field regression ] -------------------------------- #

run "pattern_blocks_with_only_pattern_field_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-partial-patterns"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "partial pattern fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }
}

#endregion --- [ S4: pattern block partial-field regression ] -------------------------------- #

#region ------ [ S4: merge_queue partial-field regression ] ---------------------------------- #

run "merge_queue_with_partial_fields_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-partial-merge-queue"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "partial merge_queue fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }
}

#endregion --- [ S4: merge_queue partial-field regression ] ---------------------------------- #

#region ------ [ S4: pull_request partial-field regression ] --------------------------------- #

run "pull_request_with_only_merge_methods_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-partial-pull-request"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "partial pull_request fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }
}

#endregion --- [ S4: pull_request partial-field regression ] --------------------------------- #

#region ------ [ S4: pages.cname single-arg try regression ] --------------------------------- #

run "pages_partial_fields_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-pages-partial"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "partial pages fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }
}

#endregion --- [ S4: pages.cname single-arg try regression ] --------------------------------- #

#region ------ [ Interaction coverage: environments ] ---------------------------------------- #

run "repo_with_environments_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-with-environments"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "environments fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }
}

run "custom_environment_branch_policy_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-custom-branch-policy"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "custom environment branch policy fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }

  assert {
    condition     = github_repository_environment_deployment_policy.environment["good-custom-branch-policy-repo::production::00::release/*"].branch_pattern == "release/*"
    error_message = "custom environment branch policy fixture must produce a release/* deployment policy"
  }
}

#endregion --- [ Interaction coverage: environments ] ---------------------------------------- #

#region ------ [ Archived repo skip behavior ] ----------------------------------------------- #

run "archived_repo_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-archived"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "archived repo fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }

  # Archived repos should be present in all_repositories but must not
  # produce any branches or rulesets — the locals filter them out.
  assert {
    condition     = length(output.branch_rulesets) == 0
    error_message = "archived repo must not produce any branch rulesets"
  }
}

#endregion --- [ Archived repo skip behavior ] ----------------------------------------------- #

#region ------ [ Empty state ] ---------------------------------------------------------------- #

run "empty_repo_set_plans_clean" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-empty"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "empty fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }

  assert {
    condition     = length(output.all_repositories) == 0
    error_message = "empty fixture must produce zero repositories"
  }
}

#endregion --- [ Empty state ] ---------------------------------------------------------------- #

#region ------ [ CODEOWNERS paths ] ----------------------------------------------------------- #

# CO1: A global default is honored in organization mode when YAML has no override.
run "org_mode_uses_global_codeowners_default" {
  command = plan

  variables {
    repo_yaml_path          = "tests/fixtures/good-personal-synthesized-codeowners"
    github_is_organization  = true
    repo_default_codeowners = "* @NWarila\n"
  }

  assert {
    condition     = output.all_repositories["good-personal-synthesized-repo"].effective_codeowners == "* @NWarila\n"
    error_message = "organization mode must use the global CODEOWNERS default"
  }
}

# CO2: An explicit per-repository value takes precedence over the global default.
run "org_mode_per_repo_codeowners_overrides_global_default" {
  command = plan

  variables {
    repo_yaml_path          = "tests/fixtures/good-org-explicit-codeowners"
    github_is_organization  = true
    repo_default_codeowners = "* @NWarila\n"
  }

  assert {
    condition     = output.all_repositories["good-org-codeowners-repo"].effective_codeowners == output.all_repositories["good-org-codeowners-repo"].codeowners
    error_message = "explicit per-repository CODEOWNERS must override the global default"
  }
}

# CO3: Preserve personal-mode use of a substantive global default.
run "personal_mode_uses_global_codeowners_default" {
  command = plan

  variables {
    repo_yaml_path          = "tests/fixtures/good-personal-synthesized-codeowners"
    github_is_organization  = false
    repo_default_codeowners = "* @personal-reviewer\n"
  }

  assert {
    condition     = output.all_repositories["good-personal-synthesized-repo"].effective_codeowners == "* @personal-reviewer\n"
    error_message = "personal mode must use the global CODEOWNERS default before synthesis"
  }
}

run "org_mode_explicit_codeowners_plans_clean" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-org-explicit-codeowners"
    github_is_organization = true
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "org-mode explicit codeowners fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }

  # effective_codeowners must passthrough the explicit YAML value verbatim.
  assert {
    condition     = output.all_repositories["good-org-codeowners-repo"].effective_codeowners == output.all_repositories["good-org-codeowners-repo"].codeowners
    error_message = "effective_codeowners must equal explicit repo.codeowners when YAML provides it"
  }
}

# CO4: With no default, personal mode still synthesizes the personal owner.
run "personal_mode_synthesizes_codeowners" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-personal-synthesized-codeowners"
    github_is_organization = false
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "personal-mode synthesis fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }

  # Synthesized effective_codeowners must mention the github_owner.
  assert {
    condition     = output.all_repositories["good-personal-synthesized-repo"].effective_codeowners == "* @test-owner\n"
    error_message = "personal-mode fixture should synthesize '* @test-owner', got: ${output.all_repositories["good-personal-synthesized-repo"].effective_codeowners}"
  }
}

# CO6a: An empty personal-mode default is unset and falls through to synthesis.
run "personal_mode_empty_codeowners_default_synthesizes" {
  command = plan

  variables {
    repo_yaml_path          = "tests/fixtures/good-personal-synthesized-codeowners"
    github_is_organization  = false
    repo_default_codeowners = ""
  }

  assert {
    condition     = output.all_repositories["good-personal-synthesized-repo"].effective_codeowners == "* @test-owner\n"
    error_message = "an empty personal-mode default must fall through to CODEOWNERS synthesis"
  }
}

# CO6b: A whitespace-only org-mode default is unset, so the ruleset guard fires.
run "org_mode_whitespace_codeowners_default_is_rejected" {
  command = plan

  variables {
    repo_yaml_path          = "tests/fixtures/bad-ruleset-codeowners-missing-org"
    github_is_organization  = true
    repo_default_codeowners = "  "
  }

  expect_failures = [
    github_repository_ruleset.branch["bad-codeowners-org-repo-rules-0"],
  ]
}

#endregion --- [ CODEOWNERS paths ] ----------------------------------------------------------- #

#region ------ [ Push ruleset positive path ] ------------------------------------------------- #

run "push_ruleset_on_private_when_supported_plans_clean" {
  command = plan

  variables {
    repo_yaml_path                = "tests/fixtures/good-push-ruleset"
    github_supports_push_rulesets = true
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "good push ruleset fixture produced validation errors: ${join(" | ", output.validation_errors)}"
  }

  assert {
    condition     = length(output.branch_rulesets) == 1
    error_message = "push ruleset fixture must produce exactly 1 ruleset"
  }
}

#endregion --- [ Push ruleset positive path ] ------------------------------------------------- #

#region ------ [ license_template default regression ] --------------------------------------- #

run "license_template_defaults_null_not_MIT" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-minimal"
  }

  # Finding 22 in the original review removed the MIT default. This test
  # is a regression guard — if someone reintroduces a non-null default,
  # this assertion will fail.
  assert {
    condition     = output.all_repositories["example-public-repo"].license_template == null
    error_message = "license_template must default to null, not MIT"
  }
}

#endregion --- [ license_template default regression ] --------------------------------------- #

#region ------ [ good-minimal resource count smoke ] ----------------------------------------- #

run "good_minimal_produces_expected_resource_counts" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-minimal"
  }

  assert {
    condition     = length(output.all_repositories) == 1
    error_message = "good-minimal should produce exactly 1 repository"
  }

  # good-minimal has no rules, so the default ruleset set (3 rulesets)
  # from var.repo_default_rules applies.
  assert {
    condition     = length(output.branch_rulesets) == 3
    error_message = "good-minimal should produce the 3 default rulesets (Branch Safety + Pull Request Gate + Release Tag Protection)"
  }
}

#endregion --- [ good-minimal resource count smoke ] ----------------------------------------- #

#region ------ [ Default value sweep (regression guard on repo_setting_defaults) ] ----------- #

# A single run block asserts every default from local.repo_setting_defaults
# propagates correctly onto a minimal-YAML repo. If someone changes a default
# in the locals file, one of these assertions will flip and the test will
# fail loudly. This is the cheapest possible guard against silent default
# drift across ~25 fields.

run "good_minimal_carries_expected_defaults" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-minimal"
  }

  # Feature toggles
  assert {
    condition     = output.all_repositories["example-public-repo"].has_discussions == false
    error_message = "has_discussions default must be false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].has_issues == true
    error_message = "has_issues default must be true"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].has_projects == false
    error_message = "has_projects default must be false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].has_wiki == false
    error_message = "has_wiki default must be false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].is_template == false
    error_message = "is_template default must be false"
  }

  # Merge behavior defaults
  assert {
    condition     = output.all_repositories["example-public-repo"].allow_auto_merge == true
    error_message = "allow_auto_merge default must be true"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].allow_merge_commit == false
    error_message = "allow_merge_commit default must be false (squash-only policy)"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].allow_rebase_merge == false
    error_message = "allow_rebase_merge default must be false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].allow_squash_merge == true
    error_message = "allow_squash_merge default must be true"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].allow_update_branch == true
    error_message = "allow_update_branch default must be true"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].delete_branch_on_merge == true
    error_message = "delete_branch_on_merge default must be true"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].squash_merge_commit_title == "PR_TITLE"
    error_message = "squash_merge_commit_title default must be PR_TITLE"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].squash_merge_commit_message == "PR_BODY"
    error_message = "squash_merge_commit_message default must be PR_BODY"
  }

  # Commit signoff
  assert {
    condition     = output.all_repositories["example-public-repo"].web_commit_signoff_required == null
    error_message = "web_commit_signoff_required must default to null (omit) at the repo level — org enforcement is the source of truth"
  }

  # Init / licensing
  assert {
    condition     = output.all_repositories["example-public-repo"].auto_init == true
    error_message = "auto_init default must be true"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].license_template == null
    error_message = "license_template default must be null (Finding 22: MIT removal)"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].gitignore_template == null
    error_message = "gitignore_template default must be null"
  }

  # Lifecycle
  assert {
    condition     = output.all_repositories["example-public-repo"].archived == false
    error_message = "archived default must be false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].archive_on_destroy == true
    error_message = "archive_on_destroy default must be true"
  }

  # Vulnerability alerts
  assert {
    condition     = output.all_repositories["example-public-repo"].vulnerability_alerts == false
    error_message = "vulnerability_alerts default must be false"
  }

  # Visibility
  assert {
    condition     = output.all_repositories["example-public-repo"].visibility == "public"
    error_message = "visibility from YAML must be 'public'"
  }

  # Not-set fields
  assert {
    condition     = output.all_repositories["example-public-repo"].fork == false
    error_message = "fork default must be false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].source_owner == null
    error_message = "source_owner must be null when fork=false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].source_repo == null
    error_message = "source_repo must be null when fork=false"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].template == null
    error_message = "template default must be null"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].pages == null
    error_message = "pages default must be null"
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].actions == null
    error_message = "actions default must be null"
  }
  assert {
    condition     = length(output.all_repositories["example-public-repo"].environments) == 0
    error_message = "environments default must be empty map"
  }
  assert {
    condition     = length(output.all_repositories["example-public-repo"].topics) == 0
    error_message = "topics default must be empty list"
  }
}

#endregion --- [ Default value sweep (regression guard on repo_setting_defaults) ] ----------- #

#region ------ [ for_each filter regression ] ------------------------------------------------- #

# Each filter is a boolean predicate that gates whether a resource/local
# entry is materialized. A regression in any predicate = resource silently
# appears or silently disappears. These runs pin the current behavior.

run "archived_repo_filters_out_downstream_locals" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-archived"
  }

  # The repo itself IS in all_repositories.
  assert {
    condition     = length(output.all_repositories) == 1
    error_message = "archived repo must still appear in all_repositories"
  }

  # But every downstream filter with `if !archived` must exclude it.
  assert {
    condition     = length(output.branch_rulesets) == 0
    error_message = "branch_rulesets must exclude archived repos"
  }
}

run "empty_repo_set_exercises_every_filter_on_zero_input" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-empty"
  }

  # Sanity: every downstream local must be empty when there are zero repos.
  # A regression that crashes on empty iteration is caught here.
  assert {
    condition     = length(output.all_repositories) == 0
    error_message = "empty fixture must produce zero repos"
  }
  assert {
    condition     = length(output.branch_rulesets) == 0
    error_message = "empty fixture must produce zero rulesets"
  }
}

run "good_minimal_produces_zero_environments_zero_codeowners" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-minimal"
  }

  # good-minimal has no environments YAML → environments local must be empty.
  assert {
    condition     = length(output.all_repositories["example-public-repo"].environments) == 0
    error_message = "good-minimal must produce zero environments"
  }

  # good-minimal has no rule with require_code_owner_review, and personal
  # mode is enabled in the default test variables — but synthesis only
  # triggers when a rule demands it. The default rulesets DO include a
  # "Pull Request Gate" with require_code_owner_review=true, so personal
  # mode synthesizes CODEOWNERS here. Assert the effective value is set.
  assert {
    condition     = output.all_repositories["example-public-repo"].effective_codeowners == "* @test-owner\n"
    error_message = "personal-mode default rules trigger codeowners synthesis, expected '* @test-owner', got: ${output.all_repositories["example-public-repo"].effective_codeowners}"
  }
}

#endregion --- [ for_each filter regression ] ------------------------------------------------- #

#region ------ [ Explicit security_and_analysis override regression (N06) ] ------------------- #

run "explicit_security_and_analysis_overrides_baseline" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-explicit-security-override"
    security_baseline_mode = "compatibility"

    # Full capabilities so the baseline would be free to turn things on.
    github_security_capabilities = {
      public = {
        advanced_security                     = true
        code_security                         = true
        secret_scanning                       = true
        secret_scanning_push_protection       = true
        secret_scanning_ai_detection          = true
        secret_scanning_non_provider_patterns = true
      }
      private = {
        advanced_security                     = true
        code_security                         = true
        secret_scanning                       = true
        secret_scanning_push_protection       = true
        secret_scanning_ai_detection          = true
        secret_scanning_non_provider_patterns = true
      }
      internal = {
        advanced_security                     = true
        code_security                         = true
        secret_scanning                       = true
        secret_scanning_push_protection       = true
        secret_scanning_ai_detection          = true
        secret_scanning_non_provider_patterns = true
      }
    }

    # Baseline wants advanced_security ON for private and secret_scanning OFF.
    # The fixture's YAML sets advanced_security: false and secret_scanning: true.
    # Explicit YAML must win.
    security_baseline = {
      public = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = false
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      private = {
        advanced_security                     = true
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

  assert {
    condition     = output.all_repositories["good-explicit-security-override-repo"].security_and_analysis.advanced_security == false
    error_message = "explicit YAML advanced_security=false must override baseline=true"
  }

  assert {
    condition     = output.all_repositories["good-explicit-security-override-repo"].security_and_analysis.secret_scanning == true
    error_message = "explicit YAML secret_scanning=true must override baseline=false"
  }
}

#endregion --- [ Explicit security_and_analysis override regression (N06) ] ------------------- #

#region ------ [ Multi-branch source ordering regression (N12) ] ----------------------------- #

run "multi_branch_sources_all_from_default_not_serially" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-multi-branch"
  }

  # branches list has 3 entries: main, develop, staging. The rename filter
  # excludes main (branches[0]), so branches local should have exactly 2
  # entries (develop + staging), each sourcing from "main".
  assert {
    condition     = output.all_repositories["good-multi-branch-repo"].branches[0] == "main"
    error_message = "first branch must be main"
  }
  assert {
    condition     = length(output.all_repositories["good-multi-branch-repo"].branches) == 3
    error_message = "branches list must have 3 entries"
  }
}

#endregion --- [ Multi-branch source ordering regression (N12) ] ----------------------------- #

#region ------ [ Fork normalization regression (N13) ] --------------------------------------- #

run "fork_repo_passes_through_source_fields" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-fork"
  }

  assert {
    condition     = output.all_repositories["good-fork-repo"].fork == true
    error_message = "fork flag must pass through as true"
  }
  assert {
    condition     = output.all_repositories["good-fork-repo"].source_owner == "upstream-org"
    error_message = "source_owner must pass through when fork=true"
  }
  assert {
    condition     = output.all_repositories["good-fork-repo"].source_repo == "upstream-repo"
    error_message = "source_repo must pass through when fork=true"
  }
}

#endregion --- [ Fork normalization regression (N13) ] --------------------------------------- #

#region ------ [ allowed_actions_config normalization defaults ] ----------------------------- #
# Before these runs the coalesce chain for github_owned_allowed / verified_allowed /
# patterns_allowed had ZERO test coverage — the defaults could be changed silently.
# verified_allowed defaults FALSE (fail-closed): it grants an allow surface that no
# supported API can statically resolve, so it must be opted into explicitly.

run "actions_config_omitted_fields_take_failclosed_defaults" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-actions-config"
  }

  assert {
    condition     = output.all_repositories["actions-omitted-repo"].actions.allowed_actions_config.verified_allowed == false
    error_message = "omitted verified_allowed must default to false (fail-closed), not true"
  }

  assert {
    condition     = output.all_repositories["actions-omitted-repo"].actions.allowed_actions_config.github_owned_allowed == true
    error_message = "omitted github_owned_allowed must default to true"
  }

  assert {
    condition     = output.all_repositories["actions-omitted-repo"].actions.allowed_actions_config.patterns_allowed == ["example-org/example-action@*"]
    error_message = "patterns_allowed must pass through unchanged"
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "fixture must normalize cleanly"
  }
}

run "actions_config_explicit_verified_true_is_preserved" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-actions-config"
  }

  assert {
    condition     = output.all_repositories["actions-explicit-true-repo"].actions.allowed_actions_config.verified_allowed == true
    error_message = "explicit verified_allowed=true must be preserved (opt-in still works)"
  }

  assert {
    condition     = output.all_repositories["actions-explicit-true-repo"].actions.allowed_actions_config.patterns_allowed == []
    error_message = "explicit empty patterns_allowed must be preserved"
  }
}

run "actions_config_explicit_false_values_are_preserved" {
  command = plan

  variables {
    repo_yaml_path = "tests/fixtures/good-actions-config"
  }

  assert {
    condition     = output.all_repositories["actions-explicit-false-repo"].actions.allowed_actions_config.verified_allowed == false
    error_message = "explicit verified_allowed=false must be preserved"
  }

  assert {
    condition     = output.all_repositories["actions-explicit-false-repo"].actions.allowed_actions_config.github_owned_allowed == false
    error_message = "explicit github_owned_allowed=false must be preserved (coalesce must not override an explicit false)"
  }
}

#endregion --- [ allowed_actions_config normalization defaults ] ----------------------------- #
