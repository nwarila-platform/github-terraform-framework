#region ------ [ Custom Variables ] ---------------------------------------------------------- #

variable "github_owner" {
  description = "GitHub organization or user account name"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.github_owner))
    error_message = "github_owner must be a valid GitHub username (alphanumeric and hyphens, cannot start/end with hyphen)."
  }
}

variable "github_is_organization" {
  description = "Whether the github_owner is an organization (true) or personal account (false). Controls org-only features and CODEOWNERS synthesis behavior."
  type        = bool
  default     = false
}

variable "github_supports_push_rulesets" {
  description = "Whether the current GitHub owner and plan support push rulesets. GitHub currently limits them to Team-plan internal/private repositories and their forks."
  type        = bool
  default     = false
}

variable "repo_yaml_path" {
  description = "Path (relative to the module root) containing the repos/ tree to ingest. Default 'repos' matches the production layout. Overridden by terraform test runs to point at fixture directories under tests/fixtures/<case>."
  type        = string
  default     = "repos"
}

#endregion --- [ Custom Variables ] ---------------------------------------------------------- #

#region ------ [ Authentication ] ------------------------------------------------------------ #

variable "github_auth_mode" {
  description = "Provider authentication mode. Must be either 'app' (GitHub App installation, preferred) or 'token' (classic or fine-grained PAT, break-glass only)."
  type        = string
  default     = "token"

  validation {
    condition     = contains(["app", "token"], var.github_auth_mode)
    error_message = "github_auth_mode must be one of: app, token."
  }
}

variable "github_token" {
  description = "GitHub Personal Access Token for authentication. Required when github_auth_mode = 'token'. Must be null when github_auth_mode = 'app'."
  type        = string
  sensitive   = true
  default     = null
}

variable "github_app_auth" {
  description = "GitHub App authentication config. Required when github_auth_mode = 'app'. Must be null when github_auth_mode = 'token'. pem_file accepts PEM contents as a string."
  type = object({
    id              = string
    installation_id = string
    pem_file        = string
  })
  sensitive = true
  default   = null
}

#endregion --- [ Authentication ] ------------------------------------------------------------ #

#region ------ [ CODEOWNERS ] ---------------------------------------------------------------- #

variable "repo_default_codeowners" {
  description = "Default CODEOWNERS content used for personal-account repositories when a repo enables require_code_owner_review but does not set 'codeowners' in its YAML. Set to null to force explicit per-repo codeowners even on personal accounts."
  type        = string
  default     = null
}

#endregion --- [ CODEOWNERS ] ---------------------------------------------------------------- #

#region ------ [ Security Baseline ] --------------------------------------------------------- #

variable "security_baseline_mode" {
  description = "Controls how the framework reconciles repo security_and_analysis against github_security_capabilities. 'strict' fails plan when a required baseline setting exceeds declared capabilities. 'compatibility' emits an advisory preview via a check block and leaves unsupported settings unset. Default is 'compatibility' to allow non-breaking rollout; flip to 'strict' in the next tagged release."
  type        = string
  default     = "compatibility"

  validation {
    condition     = contains(["strict", "compatibility"], var.security_baseline_mode)
    error_message = "security_baseline_mode must be one of: strict, compatibility."
  }
}

variable "github_security_capabilities" {
  description = "Baseline-path capability matrix for GitHub security_and_analysis features, keyed by repository visibility. This gates only baseline enablement; an explicit repository YAML true intentionally bypasses a false capability as the sanctioned, PR-reviewed opt-in. Private/internal secret scanning and push protection are paid Secret Protection features."

  type = object({
    public = object({
      advanced_security                     = bool
      code_security                         = bool
      secret_scanning                       = bool
      secret_scanning_push_protection       = bool
      secret_scanning_ai_detection          = bool
      secret_scanning_non_provider_patterns = bool
    })
    private = object({
      advanced_security                     = bool
      code_security                         = bool
      secret_scanning                       = bool
      secret_scanning_push_protection       = bool
      secret_scanning_ai_detection          = bool
      secret_scanning_non_provider_patterns = bool
    })
    internal = object({
      advanced_security                     = bool
      code_security                         = bool
      secret_scanning                       = bool
      secret_scanning_push_protection       = bool
      secret_scanning_ai_detection          = bool
      secret_scanning_non_provider_patterns = bool
    })
  })

  # Capabilities gate ONLY the baseline path. Explicit YAML true bypasses a
  # false capability intentionally; its reviewed PR is the cost authorization.
  # Secret scanning and push protection are free for public repositories but
  # paid Secret Protection features for private/internal repositories.
  default = {
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

variable "security_baseline" {
  description = "Desired security_and_analysis baseline the framework should enforce when the owner's github_security_capabilities allow it, keyed by visibility. Fully-required matrix. A feature set to true means 'enable this wherever capabilities permit'; false means 'leave this feature unmanaged (do not enable)'. Explicit per-repo security_and_analysis YAML still overrides this baseline; per-repo unmanaged_security_features overrides both and emits null so the provider omits the feature."

  type = object({
    public = object({
      advanced_security                     = bool
      code_security                         = bool
      secret_scanning                       = bool
      secret_scanning_push_protection       = bool
      secret_scanning_ai_detection          = bool
      secret_scanning_non_provider_patterns = bool
    })
    private = object({
      advanced_security                     = bool
      code_security                         = bool
      secret_scanning                       = bool
      secret_scanning_push_protection       = bool
      secret_scanning_ai_detection          = bool
      secret_scanning_non_provider_patterns = bool
    })
    internal = object({
      advanced_security                     = bool
      code_security                         = bool
      secret_scanning                       = bool
      secret_scanning_push_protection       = bool
      secret_scanning_ai_detection          = bool
      secret_scanning_non_provider_patterns = bool
    })
  })

  # Free-only baseline: public secret scanning and push protection are on;
  # paid features and all private/internal features are off.
  default = {
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

variable "security_default_status" {
  description = "Fallback for security features not resolved by unmanaged/excluded, explicit YAML, or enabled baseline: 'disabled' manages them as false; 'unmanaged' emits null. Explicit YAML and unmanaged_security_features retain higher precedence."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "unmanaged"], var.security_default_status)
    error_message = "security_default_status must be one of: disabled, unmanaged."
  }
}

variable "security_pin_exclude" {
  description = "Fleet-wide security feature names to omit (null), after per-repo unmanaged features and before explicit YAML. Unknown names are rejected by framework validation."
  type        = list(string)
  default     = []
}

#endregion --- [ Security Baseline ] --------------------------------------------------------- #

#region ------ [ Default Values ] ------------------------------------------------------------ #

variable "repo_default_branches" {
  description = "Default branch list applied when a repo YAML does not explicitly define branches."
  type        = list(string)
  default     = ["main"]
}

variable "repo_default_rules" {
  description = "Default repository rulesets applied when a repo YAML does not explicitly define rules."

  type = list(
    object({
      name        = optional(string)
      target      = optional(string)
      enforcement = optional(string)

      bypass_actors = optional(
        list(
          object({
            actor_id    = number
            actor_type  = string
            bypass_mode = optional(string)
          })
        ),
        []
      )

      conditions = optional(
        object({
          include = list(string)
          exclude = optional(list(string), [])
        })
      )

      rules = object({
        creation                = optional(bool)
        update                  = optional(bool)
        deletion                = optional(bool)
        non_fast_forward        = optional(bool)
        required_linear_history = optional(bool)
        required_signatures     = optional(bool)

        pull_request = optional(
          object({
            allowed_merge_methods             = list(string)
            dismiss_stale_reviews_on_push     = optional(bool)
            require_code_owner_review         = optional(bool)
            require_last_push_approval        = optional(bool)
            required_approving_review_count   = optional(number)
            required_review_thread_resolution = optional(bool)
          })
        )

        copilot_code_review = optional(
          object({
            review_on_push             = optional(bool)
            review_draft_pull_requests = optional(bool)
          })
        )

        required_status_checks = optional(
          object({
            required_check = optional(
              list(
                object({
                  context        = string
                  integration_id = optional(number)
                })
              ),
              []
            )

            do_not_enforce_on_create             = optional(bool)
            strict_required_status_checks_policy = optional(bool)
          })
        )

        required_deployments = optional(
          object({
            required_deployment_environments = list(string)
          })
        )

        required_code_scanning = optional(
          object({
            required_code_scanning_tool = list(
              object({
                tool                      = string
                alerts_threshold          = optional(string)
                security_alerts_threshold = optional(string)
              })
            )
          })
        )

        merge_queue = optional(
          object({
            check_response_timeout_minutes    = optional(number)
            grouping_strategy                 = optional(string)
            max_entries_to_build              = optional(number)
            max_entries_to_merge              = optional(number)
            merge_method                      = optional(string)
            min_entries_to_merge              = optional(number)
            min_entries_to_merge_wait_minutes = optional(number)
          })
        )

        branch_name_pattern = optional(
          object({
            operator = string
            pattern  = string
            name     = optional(string)
            negate   = optional(bool)
          })
        )

        commit_author_email_pattern = optional(
          object({
            operator = string
            pattern  = string
            name     = optional(string)
            negate   = optional(bool)
          })
        )

        committer_email_pattern = optional(
          object({
            operator = string
            pattern  = string
            name     = optional(string)
            negate   = optional(bool)
          })
        )

        commit_message_pattern = optional(
          object({
            operator = string
            pattern  = string
            name     = optional(string)
            negate   = optional(bool)
          })
        )

        tag_name_pattern = optional(
          object({
            operator = string
            pattern  = string
            name     = optional(string)
            negate   = optional(bool)
          })
        )

        update_allows_fetch_and_merge = optional(bool)

        file_path_restriction = optional(
          object({
            restricted_file_paths = list(string)
          })
        )

        file_extension_restriction = optional(
          object({
            restricted_file_extensions = list(string)
          })
        )

        max_file_size = optional(
          object({
            max_file_size = number
          })
        )

        max_file_path_length = optional(
          object({
            max_file_path_length = number
          })
        )
      })
    })
  )

  # Golden baseline rulesets for a solo-operator personal-account org.
  #
  # Design contract:
  #   - Owner (RepositoryRole 5 = Admin) bypasses both rulesets. They USE
  #     PRs by discipline for normal work; bypass exists for emergencies
  #     (e.g., force-pushing a secrets cleanup to main).
  #   - External contributors face the full ruleset: PRs required, 1
  #     approval from the owner, status checks, conversation resolution,
  #     code-owner review. Nothing reaches main without the owner's
  #     explicit action.
  #   - Repos that need stricter self-enforcement (e.g., remove the owner
  #     from bypass_actors) override in their YAML.
  #
  # Why bypass_mode = "always" on both rulesets:
  #   GitHub rulesets bypass is all-or-nothing per ruleset per actor.
  #   There is no "bypass update but not pull_request within the same
  #   ruleset." To allow emergency direct pushes, the owner must bypass
  #   Branch Safety (which blocks update). But a direct push also hits
  #   the PR Gate (which requires a pull_request). If the owner doesn't
  #   bypass the PR Gate, emergency pushes are blocked. Putting the
  #   owner in bypass on both rulesets is the only way to enable
  #   emergency direct pushes while keeping the PR gate enforced for
  #   external contributors.
  default = [
    {
      name        = "Branch Safety"
      target      = "branch"
      enforcement = "active"
      bypass_actors = [
        {
          actor_id    = 5
          actor_type  = "RepositoryRole"
          bypass_mode = "always"
        }
      ]
      conditions = {
        include = ["~DEFAULT_BRANCH"]
        exclude = []
      }

      rules = {
        creation                = true
        update                  = true
        deletion                = true
        non_fast_forward        = true
        required_linear_history = true
        required_signatures     = true
      }
    },
    {
      name        = "Pull Request Gate"
      target      = "branch"
      enforcement = "active"
      bypass_actors = [
        {
          actor_id    = 5
          actor_type  = "RepositoryRole"
          bypass_mode = "always"
        }
      ]
      conditions = {
        include = ["~DEFAULT_BRANCH"]
        exclude = []
      }

      rules = {
        pull_request = {
          allowed_merge_methods             = ["squash"]
          dismiss_stale_reviews_on_push     = true
          require_code_owner_review         = true
          require_last_push_approval        = true
          required_approving_review_count   = 1
          required_review_thread_resolution = true
        }
      }
    },
    {
      # Release Tag Protection.
      #
      # Applies to every tag in the repository. Blocks tag deletion and tag
      # force-moves (so a pushed release cannot be silently replaced) and
      # requires tag commits/annotations to be signed (so tag provenance is
      # verifiable). Tag *creation* is intentionally left allowed so the
      # normal release workflow works without bypass.
      #
      # Admin bypass exists for emergency remediation (e.g., deleting a tag
      # that accidentally embedded a leaked secret or removing a tag pushed
      # to the wrong SHA).
      name        = "Release Tag Protection"
      target      = "tag"
      enforcement = "active"
      bypass_actors = [
        {
          actor_id    = 5
          actor_type  = "RepositoryRole"
          bypass_mode = "always"
        }
      ]
      conditions = {
        include = ["~ALL"]
        exclude = []
      }

      rules = {
        deletion            = true
        non_fast_forward    = true
        required_signatures = true
      }
    }
  ]
}

#endregion --- [ Default Values ] ------------------------------------------------------------ #
