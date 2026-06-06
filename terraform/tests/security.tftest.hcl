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
}

#endregion --- [ Baseline feature enabled when capability matches ] -------------------------- #
