#region ------ [ Custom Variables ] ---------------------------------------------------------- #

variable "github_token" {
  description = "GitHub Personal Access Token for authentication"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub organization or user account name"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", var.github_owner))
    error_message = "github_owner must be a valid GitHub username (alphanumeric and hyphens, cannot start/end with hyphen)."
  }
}

variable "github_is_organization" {
  description = "Whether the github_owner is an organization (true) or personal account (false). Controls org-only features like allow_forking."
  type        = bool
  default     = false
}

variable "github_supports_push_rulesets" {
  description = "Whether the current GitHub owner and plan support push rulesets. GitHub currently limits them to Team-plan internal/private repositories and their forks."
  type        = bool
  default     = false
}

#endregion --- [ Custom Variables ] ---------------------------------------------------------- #

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

  default = [
    {
      name        = "Default Branch Protection"
      target      = "branch"
      enforcement = "active"
      conditions = {
        include = ["~DEFAULT_BRANCH"]
        exclude = []
      }

      rules = {
        creation                = true
        update                  = false
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
          bypass_mode = "pull_request"
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
    }
  ]
}

#endregion --- [ Default Values ] ------------------------------------------------------------ #
