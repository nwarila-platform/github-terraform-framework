# #region ------ [ Custom Variables ] ---------------------------------------------------------- #

# variable "all_repositories" {

#   description = "Definitions for github_repository (non-deprecated arguments only)."

#   type = list(
#     object({
#       /* Required */
#       name = string

#       /* Optional */
#       description  = optional(string)
#       homepage_url = optional(string)

#       # Forks
#       fork         = optional(bool)
#       source_owner = optional(string)
#       source_repo  = optional(string)

#       # Visibility / features
#       visibility      = optional(string)
#       has_issues      = optional(bool)
#       has_discussions = optional(bool)
#       has_projects    = optional(bool)
#       has_wiki        = optional(bool)
#       is_template     = optional(bool)

#       # Merge behavior
#       allow_auto_merge            = optional(bool)
#       allow_forking               = optional(bool)
#       allow_merge_commit          = optional(bool)
#       allow_rebase_merge          = optional(bool)
#       allow_squash_merge          = optional(bool)
#       allow_update_branch         = optional(bool)
#       delete_branch_on_merge      = optional(bool)
#       merge_commit_message        = optional(string)
#       merge_commit_title          = optional(string)
#       squash_merge_commit_message = optional(string)
#       squash_merge_commit_title   = optional(string)
#       web_commit_signoff_required = optional(bool)

#       # Initialization / licensing
#       auto_init          = optional(bool)
#       gitignore_template = optional(string)
#       license_template   = optional(string)

#       # Lifecycle
#       archived           = optional(bool)
#       archive_on_destroy = optional(bool)

#       # Topics
#       topics = optional(set(string), [])

#       # Dependabot / vuln alerts
#       vulnerability_alerts                    = optional(bool)
#       ignore_vulnerability_alerts_during_read = optional(bool)

#       pages = optional(
#         object({
#           source = optional(
#             object({
#               branch = string
#               path   = optional(string)
#             })
#           )
#           build_type = optional(string)
#           cname      = optional(string)
#         })
#       )

#       security_and_analysis = optional(
#         object({
#           advanced_security                     = optional(bool)
#           code_security                         = optional(bool)
#           secret_scanning                       = optional(bool)
#           secret_scanning_push_protection       = optional(bool)
#           secret_scanning_ai_detection          = optional(bool)
#           secret_scanning_non_provider_patterns = optional(bool)
#         })
#       )

#       template = optional(
#         object({
#           owner                = string
#           repository           = string
#           include_all_branches = optional(bool)
#         })
#       )

#       branches = optional(
#         list(
#           object({
#             # The branch name (e.g., DEV, TEST, PROD, INT, main)
#             name = string

#             # Optional per-branch ruleset definition (maps to github_repository_ruleset)
#             ruleset = optional(
#               object({
#                 # Ruleset metadata
#                 name        = optional(string)
#                 enforcement = optional(string)

#                 bypass_actors = optional(
#                   list(
#                     object({
#                       actor_id   = number
#                       actor_type = string
#                       bypass_mode = optional(string) # e.g., "always"
#                     })
#                   )
#                 )

#                 conditions = optional(
#                   object({
#                     ref_name = object({
#                       include = list(string)
#                       exclude = list(string)
#                     })
#                   })
#                 )

#                 # Rules block (what you enforce)
#                 rules = optional(
#                   object({
#                     # --- Common branch safety rules ---
#                     creation                = optional(bool)
#                     update                  = optional(bool)
#                     deletion                = optional(bool)
#                     non_fast_forward        = optional(bool)
#                     required_linear_history = optional(bool)
#                     required_signatures     = optional(bool)

#                     # --- Pull request gatekeeping ---
#                     pull_request = optional(
#                       object({
#                         allowed_merge_methods             = list(string)
#                         dismiss_stale_reviews_on_push     = optional(bool)
#                         require_code_owner_review         = optional(bool)
#                         require_last_push_approval        = optional(bool)
#                         required_approving_review_count   = optional(number)
#                         required_review_thread_resolution = optional(bool)
#                       })
#                     )

#                     # --- review setting ---
#                     copilot_code_review = optional(
#                       object({
#                         review_on_push             = optional(bool)
#                         review_draft_pull_requests = optional(bool)
#                       })
#                     )

#                     # --- Required status checks ---
#                     required_status_checks = optional(
#                       object({
#                         required_check = optional(
#                           list(
#                             object({
#                               context        = string
#                               integration_id = optional(number)
#                             })
#                           )
#                         )

#                         do_not_enforce_on_create             = optional(bool)
#                         strict_required_status_checks_policy = optional(bool)
#                       })
#                     )

#                     # --- Promotion / environments gating ---
#                     required_deployments = optional(
#                       object({
#                         required_deployment_environments = list(string)
#                       })
#                     )

#                     # --- Code scanning gates ---
#                     required_code_scanning = optional(
#                       object({
#                         required_code_scanning_tool = list(
#                           object({
#                             tool                     = string
#                             alerts_threshold          = optional(string)
#                             security_alerts_threshold = optional(string)
#                           })
#                         )
#                       })
#                     )

#                     # --- Merge queue (optional) ---
#                     merge_queue = optional(
#                       object({
#                         check_response_timeout_minutes     = optional(number)
#                         grouping_strategy                  = optional(string)
#                         max_entries_to_build               = optional(number)
#                         max_entries_to_merge               = optional(number)
#                         merge_method                       = optional(string)
#                         min_entries_to_merge               = optional(number)
#                         min_entries_to_merge_wait_minutes  = optional(number)
#                       })
#                     )

#                     # --- Pattern rules (optional, but supported by rulesets) ---
#                     branch_name_pattern = optional(
#                       object({
#                         operator = string
#                         pattern  = string
#                         name     = optional(string)
#                         negate   = optional(bool)
#                       })
#                     )

#                     commit_author_email_pattern = optional(
#                       object({
#                         operator = string
#                         pattern  = string
#                         name     = optional(string)
#                         negate   = optional(bool)
#                       })
#                     )

#                     committer_email_pattern = optional(
#                       object({
#                         operator = string
#                         pattern  = string
#                         name     = optional(string)
#                         negate   = optional(bool)
#                       })
#                     )

#                     commit_message_pattern = optional(
#                       object({
#                         operator = string
#                         pattern  = string
#                         name     = optional(string)
#                         negate   = optional(bool)
#                       })
#                     )

#                     tag_name_pattern = optional(
#                       object({
#                         operator = string
#                         pattern  = string
#                         name     = optional(string)
#                         negate   = optional(bool)
#                       })
#                     )

#                     # Fork-specific
#                     update_allows_fetch_and_merge = optional(bool)

#                     # --- Push-target-only rules (only valid when ruleset target = "push") ---
#                     # Leaving these here makes the schema future-proof if you later add repo-level push rulesets.
#                     file_path_restriction = optional(
#                       object({
#                         restricted_file_paths = list(string)
#                       })
#                     )

#                     file_extension_restriction = optional(
#                       object({
#                         restricted_file_extensions = list(string)
#                       })
#                     )

#                     max_file_size = optional(
#                       object({
#                         max_file_size = number
#                       })
#                     )

#                     max_file_path_length = optional(
#                       object({
#                         max_file_path_length = number
#                       })
#                     )

#                   })
#                 )
#               })
#             )
#           })
#         )
#       )
#     })
#   )
# }

# #endregion --- [ Custom Variables ] ---------------------------------------------------------- #
