#% ========================================================================================== %#
#% = File: security.tftest.hcl                                                                 %#
#% ------------------------------------------------------------------------------------------ %#
#% Security baseline regression coverage. Covers:                                              %#
#%   - strict mode + no gap        → plan succeeds                                             %#
#%   - compatibility mode + no gap → plan succeeds, preview empty                              %#
#%   - per-visibility differentiation (gaps on public AND private)                             %#
#%   - no baseline collapses security_and_analysis to null                                     %#
#%   - baseline feature enabled when capability matches                                        %#
#%                                                                                             %#
#% NOTE: .tftest.hcl files do not support locals {} blocks, so the full capability/baseline    %#
#%   matrix is restated per run block. Verbose but unavoidable given Packer-coherence style    %#
#%   variables (no optional() means every field is required).                                  %#
#% ========================================================================================== %#

mock_provider "github" {}
mock_provider "time" {}

variables {
  github_owner           = "test-owner"
  github_is_organization = false
  github_auth_mode       = "token"
  github_token           = "fake-token-for-unit-tests"
  github_app_auth        = null

  # Default to no baseline so check.security_baseline_preview doesn't fire
  # on runs that don't explicitly override these variables.
  security_baseline = {
    public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
  }
}

#region ------ [ Strict mode, no gap — must pass ] ------------------------------------------- #

run "strict_mode_no_gap_plans_clean" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-minimal"
    security_baseline_mode = "strict"

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

    security_baseline = {
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
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "strict-mode-no-gap must plan clean. errors: ${join(" | ", output.validation_errors)}"
  }

  assert {
    condition     = length(output.security_capability_gap_preview) == 0
    error_message = "strict-mode-no-gap must produce empty preview"
  }
}

#endregion --- [ Strict mode, no gap — must pass ] ------------------------------------------- #

#region ------ [ Compatibility mode, no gap ] ------------------------------------------------ #

run "compatibility_mode_no_gap_plans_clean_with_empty_preview" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-minimal"
    security_baseline_mode = "compatibility"

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

    security_baseline = {
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
  }

  assert {
    condition     = length(output.validation_errors) == 0
    error_message = "compat-mode-no-gap must plan clean. errors: ${join(" | ", output.validation_errors)}"
  }

  assert {
    condition     = length(output.security_capability_gap_preview) == 0
    error_message = "compat-mode-no-gap must produce empty preview"
  }
}

#endregion --- [ Compatibility mode, no gap ] ------------------------------------------------ #

#region ------ [ Per-visibility differentiation ] -------------------------------------------- #

run "strict_mode_reports_gaps_across_multiple_visibilities" {
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
        secret_scanning                       = true
        secret_scanning_push_protection       = false
        secret_scanning_ai_detection          = false
        secret_scanning_non_provider_patterns = false
      }
      private = {
        advanced_security                     = true
        code_security                         = true
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

  # The check block fires as expected in compatibility mode — terraform test
  # treats check-block warnings as run failures unless we declare them.
  expect_failures = [
    check.security_baseline_preview,
  ]

  # Expect 4 gaps: 2 on public (advanced_security, secret_scanning) and
  # 2 on private (advanced_security, code_security).
  assert {
    condition     = length(output.security_capability_gap_preview) == 4
    error_message = "expected 4 capability gaps across public+private, got ${length(output.security_capability_gap_preview)}"
  }
}

#endregion --- [ Per-visibility differentiation ] -------------------------------------------- #

#region ------ [ Null baseline collapses security_and_analysis to null ] --------------------- #

run "no_baseline_no_yaml_collapses_security_to_null" {
  command = plan

  variables {
    security_default_status = "unmanaged"
    repo_yaml_path          = "tests/fixtures/good-minimal"
    security_baseline_mode  = "compatibility"

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

  assert {
    condition     = output.all_repositories["example-public-repo"].security_and_analysis == null
    error_message = "no baseline + no explicit YAML must collapse security_and_analysis to null"
  }
}

#endregion --- [ Null baseline collapses security_and_analysis to null ] --------------------- #

#region ------ [ Per-repo unmanaged security features collapse to null ] --------------------- #

run "unmanaged_secret_features_collapse_security_to_null" {
  command = plan

  variables {
    security_default_status = "unmanaged"
    repo_yaml_path          = "tests/fixtures/good-unmanaged-security-features"
    security_baseline_mode  = "strict"

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

    security_baseline = {
      public = {
        advanced_security                     = false
        code_security                         = false
        secret_scanning                       = true
        secret_scanning_push_protection       = true
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

  assert {
    condition     = output.all_repositories["unmanaged-security-repo"].security_and_analysis == null
    error_message = "unmanaged secret-scanning features must force security_and_analysis to null so the provider omits the block"
  }
}

#endregion --- [ Per-repo unmanaged security features collapse to null ] --------------------- #

#region ------ [ Baseline feature enabled when capability matches ] -------------------------- #

run "baseline_feature_enabled_when_capability_matches" {
  command = plan

  variables {
    repo_yaml_path         = "tests/fixtures/good-minimal"
    security_baseline_mode = "strict"

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

    security_baseline = {
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
  }

  assert {
    condition     = output.all_repositories["example-public-repo"].security_and_analysis.secret_scanning == true
    error_message = "baseline demanded secret_scanning=true and capability supports it, expected normalized value to be true"
  }

  assert {
    condition     = output.all_repositories["example-public-repo"].security_and_analysis.advanced_security == true
    error_message = "baseline demanded advanced_security=true and capability supports it, expected normalized value to be true"
  }

  assert {
    condition = output.all_repositories["example-public-repo"].security_and_analysis == {
      advanced_security                     = true
      code_security                         = true
      secret_scanning                       = true
      secret_scanning_push_protection       = true
      secret_scanning_ai_detection          = true
      secret_scanning_non_provider_patterns = true
    }
    error_message = "repo without unmanaged_security_features must keep the existing managed security baseline"
  }
}

#endregion --- [ Baseline feature enabled when capability matches ] -------------------------- #

run "disabled_fallback_manages_unspecified_features" {
  command = plan
  variables { repo_yaml_path = "tests/fixtures/good-minimal" }
  assert {
    condition     = output.all_repositories["example-public-repo"].security_and_analysis != null && alltrue([for v in values(output.all_repositories["example-public-repo"].security_and_analysis) : v == false])
    error_message = "disabled fallback must keep the block and manage every unspecified feature false"
  }
}

run "precedence_collisions_and_explicit_capability_bypass" {
  command = plan
  variables {
    repo_yaml_path       = "tests/fixtures/good-precedence"
    security_pin_exclude = ["code_security"]
  }
  assert {
    condition = (
      output.all_repositories["good-precedence-repo"].security_and_analysis.secret_scanning == null &&
      output.all_repositories["good-precedence-repo"].security_and_analysis.code_security == null &&
      output.all_repositories["good-precedence-repo"].security_and_analysis.advanced_security == false
    )
    error_message = "precedence must be unmanaged > exclude > explicit, while explicit false is preserved"
  }
}

run "explicit_true_bypasses_private_capability_false" {
  command = plan
  variables { repo_yaml_path = "tests/fixtures/good-precedence" }
  assert {
    condition     = output.all_repositories["good-precedence-repo"].security_and_analysis.code_security == true
    error_message = "explicit private YAML true must bypass capability=false"
  }
  assert {
    condition     = output.all_repositories["good-precedence-repo"].security_and_analysis.secret_scanning == null
    error_message = "unmanaged must beat overlapping explicit true"
  }
}

run "pin_exclude_omits_code_security" {
  command = plan
  variables {
    repo_yaml_path       = "tests/fixtures/good-minimal"
    security_pin_exclude = ["code_security"]
  }
  assert {
    condition = (
      output.all_repositories["example-public-repo"].security_and_analysis.code_security == null &&
      alltrue([for f, v in output.all_repositories["example-public-repo"].security_and_analysis : v == false if f != "code_security"])
    )
    error_message = "code_security must be omitted while disabled sibling blocks remain"
  }
}

run "all_features_excluded_collapses_whole_block" {
  command = plan
  variables {
    repo_yaml_path       = "tests/fixtures/good-minimal"
    security_pin_exclude = ["advanced_security", "code_security", "secret_scanning", "secret_scanning_push_protection", "secret_scanning_ai_detection", "secret_scanning_non_provider_patterns"]
  }
  assert {
    condition     = output.all_repositories["example-public-repo"].security_and_analysis == null
    error_message = "all excluded features must collapse the whole block to null"
  }
}

run "invalid_pin_exclude_blocks_plan" {
  command = plan
  variables {
    repo_yaml_path       = "tests/fixtures/good-minimal"
    security_pin_exclude = ["not_a_real_feature"]
  }
  expect_failures = [terraform_data.framework_validation]
}

run "dependabot_explicit_alert_opt_in_coalesces_updates" {
  command = plan
  variables { repo_yaml_path = "tests/fixtures/good-precedence" }
  assert {
    condition = (
      output.all_repositories["good-precedence-repo"].vulnerability_alerts == true &&
      output.all_repositories["good-precedence-repo"].dependabot_security_updates == true
    )
    error_message = "explicit vulnerability_alerts=true must coalesce omitted dependabot updates to true"
  }
}

run "explicit_false_beats_enabled_baseline" {
  command = plan
  variables {
    repo_yaml_path = "tests/fixtures/good-precedence"
    github_security_capabilities = {
      public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      private  = { advanced_security = true, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    }
    security_baseline = {
      public   = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      private  = { advanced_security = true, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    }
  }
  assert {
    condition     = output.all_repositories["good-precedence-repo"].security_and_analysis.advanced_security == false
    error_message = "explicit false must beat baseline true"
  }
}

run "capability_gap_disabled_falls_back_false_and_preview_fires" {
  command = plan
  variables {
    repo_yaml_path = "tests/fixtures/good-minimal"
    security_baseline = {
      public   = { advanced_security = true, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    }
  }
  expect_failures = [check.security_baseline_preview]
  assert {
    condition     = output.all_repositories["example-public-repo"].security_and_analysis.advanced_security == false
    error_message = "baseline true plus capability false must use disabled fallback false"
  }
}

run "capability_gap_unmanaged_falls_back_null" {
  command = plan
  variables {
    repo_yaml_path          = "tests/fixtures/good-minimal"
    security_default_status = "unmanaged"
    security_baseline = {
      public   = { advanced_security = true, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      private  = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
      internal = { advanced_security = false, code_security = false, secret_scanning = false, secret_scanning_push_protection = false, secret_scanning_ai_detection = false, secret_scanning_non_provider_patterns = false }
    }
  }
  expect_failures = [check.security_baseline_preview]
  assert {
    condition     = output.all_repositories["example-public-repo"].security_and_analysis == null
    error_message = "baseline true plus capability false must collapse to null in unmanaged fallback"
  }
}
