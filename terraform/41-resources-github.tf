#% ========================================================================================== %#
#% = File: 41-resources-github.tf                                                             %#
#% ------------------------------------------------------------------------------------------ %#
#% Resources driven by locals computed in locals.tf                                            %#
#% ========================================================================================== %#

# Global validation gate. A single precondition evaluates the aggregated
# local.global_validation_errors list. If any errors are present, plan fails
# with one joined message. This node handles invariants that span the whole
# configuration (duplicate repo keys, unknown nested YAML keys, unsupported
# push rulesets, auth config, strict-mode capability gaps). Per-resource
# invariants stay as lifecycle.precondition blocks on their own resources
# so error messages point at specific addresses.
#
# The input is intentionally static so this node never shows "will be
# replaced" in plan output when the error list changes.
resource "terraform_data" "framework_validation" {
  input = "framework-validation-gate"

  lifecycle {
    precondition {
      condition     = length(local.global_validation_errors) == 0
      error_message = nonsensitive("Framework validation failed:\n\n${join("\n\n", local.global_validation_errors)}")
    }
  }
}

resource "github_repository" "repo" {
  for_each = local.all_repositories

  # Required
  name = each.value.name

  # Optional
  description  = each.value.description
  homepage_url = each.value.homepage_url

  # Forks (only meaningful when fork = true)
  fork         = each.value.fork
  source_owner = each.value.source_owner
  source_repo  = each.value.source_repo

  # Visibility / Features
  visibility      = each.value.visibility
  has_issues      = each.value.has_issues
  has_discussions = each.value.has_discussions
  has_projects    = each.value.has_projects
  has_wiki        = each.value.has_wiki
  is_template     = each.value.is_template

  # Merge Behavior
  allow_merge_commit          = each.value.allow_merge_commit
  allow_squash_merge          = each.value.allow_squash_merge
  allow_rebase_merge          = each.value.allow_rebase_merge
  allow_auto_merge            = each.value.allow_auto_merge
  allow_update_branch         = each.value.allow_update_branch
  squash_merge_commit_title   = each.value.squash_merge_commit_title
  squash_merge_commit_message = each.value.squash_merge_commit_message
  merge_commit_title          = each.value.merge_commit_title
  merge_commit_message        = each.value.merge_commit_message
  delete_branch_on_merge      = each.value.delete_branch_on_merge
  web_commit_signoff_required = each.value.web_commit_signoff_required

  # Initialization / Licensing
  auto_init          = each.value.auto_init
  gitignore_template = each.value.gitignore_template
  license_template   = each.value.license_template

  # Lifecycle
  archived           = each.value.archived
  archive_on_destroy = each.value.archive_on_destroy

  # Topics
  topics = each.value.topics

  # Dependabot / Vulnerability Alerts
  vulnerability_alerts = each.value.vulnerability_alerts
  dynamic "pages" {
    for_each = each.value.pages == null ? [] : [each.value.pages]
    content {
      build_type = pages.value.build_type
      cname      = pages.value.cname

      dynamic "source" {
        for_each = pages.value.source == null ? [] : [pages.value.source]
        content {
          branch = source.value.branch
          path   = source.value.path
        }
      }
    }
  }

  dynamic "security_and_analysis" {
    for_each = each.value.security_and_analysis == null ? [] : [each.value.security_and_analysis]
    content {
      dynamic "advanced_security" {
        for_each = security_and_analysis.value.advanced_security == null ? [] : [security_and_analysis.value.advanced_security]
        content {
          status = advanced_security.value ? "enabled" : "disabled"
        }
      }

      dynamic "code_security" {
        for_each = security_and_analysis.value.code_security == null ? [] : [security_and_analysis.value.code_security]
        content {
          status = code_security.value ? "enabled" : "disabled"
        }
      }

      dynamic "secret_scanning" {
        for_each = security_and_analysis.value.secret_scanning == null ? [] : [security_and_analysis.value.secret_scanning]
        content {
          status = secret_scanning.value ? "enabled" : "disabled"
        }
      }

      dynamic "secret_scanning_push_protection" {
        for_each = security_and_analysis.value.secret_scanning_push_protection == null ? [] : [security_and_analysis.value.secret_scanning_push_protection]
        content {
          status = secret_scanning_push_protection.value ? "enabled" : "disabled"
        }
      }

      dynamic "secret_scanning_ai_detection" {
        for_each = security_and_analysis.value.secret_scanning_ai_detection == null ? [] : [security_and_analysis.value.secret_scanning_ai_detection]
        content {
          status = secret_scanning_ai_detection.value ? "enabled" : "disabled"
        }
      }

      dynamic "secret_scanning_non_provider_patterns" {
        for_each = security_and_analysis.value.secret_scanning_non_provider_patterns == null ? [] : [security_and_analysis.value.secret_scanning_non_provider_patterns]
        content {
          status = secret_scanning_non_provider_patterns.value ? "enabled" : "disabled"
        }
      }
    }
  }

  dynamic "template" {
    for_each = each.value.template == null ? [] : [each.value.template]
    content {
      owner                = template.value.owner
      repository           = template.value.repository
      include_all_branches = template.value.include_all_branches
    }
  }

  # Global validation (duplicate keys, unknown nested keys, push rulesets,
  # auth config, capability gaps) is enforced upstream by
  # terraform_data.framework_validation. Per-resource preconditions here
  # check repo-scoped invariants so their errors point at the specific
  # github_repository.repo[<name>] address.
  lifecycle {
    # GitHub only accepts allow_forking updates on organization-owned private
    # repositories. Ignore remote drift here and keep fork policy enforced by
    # visibility plus rulesets instead of making personal-account deploys fail
    # on an unsupported API field.
    ignore_changes = [auto_init, license_template, allow_forking]

    precondition {
      condition     = contains(["public", "private", "internal"], each.value.visibility)
      error_message = "Repository '${each.key}' has invalid visibility '${each.value.visibility}'. Must be one of: public, private, internal."
    }

    precondition {
      condition     = each.value.visibility != "public" || (each.value.description != null && each.value.description != "")
      error_message = "Public repository '${each.key}' must define a non-empty description."
    }
  }

  depends_on = [terraform_data.framework_validation]
}

resource "github_repository_dependabot_security_updates" "repo" {
  for_each = {
    for repository_name, repository in local.all_repositories :
    repository_name => repository
    if !repository.archived
  }

  repository = github_repository.repo[each.key].name
  enabled    = each.value.dependabot_security_updates

  depends_on = [github_repository.repo]
}

resource "github_branch_default" "default" {
  for_each = local.branch_defaults

  repository = github_repository.repo[each.value.repository].name
  branch     = each.value.branch
  rename     = each.value.rename

  depends_on = [github_repository.repo]
}

resource "time_sleep" "after_branch_default" {
  # GitHub's API is eventually consistent after a default-branch rename. Hold
  # for a short window so downstream github_branch / ruleset operations don't
  # race the rename and fail intermittently.
  depends_on      = [github_branch_default.default]
  create_duration = "15s"
}

resource "github_branch" "branches" {
  for_each = local.branches

  repository = each.value.repository
  branch     = each.value.branch

  source_branch = each.value.source_branch

  depends_on = [time_sleep.after_branch_default]
}

resource "github_repository_ruleset" "branch" {
  for_each = local.branch_rulesets

  repository  = github_repository.repo[each.value.repository].name
  name        = each.value.name
  target      = each.value.target
  enforcement = each.value.enforcement

  # Who can bypass
  dynamic "bypass_actors" {
    for_each = each.value.bypass_actors
    content {
      actor_id    = bypass_actors.value.actor_id
      actor_type  = bypass_actors.value.actor_type
      bypass_mode = bypass_actors.value.bypass_mode
    }
  }

  # Conditions (scoping)
  conditions {
    ref_name {
      include = each.value.include
      exclude = each.value.exclude
    }
  }

  # Rules
  rules {
    # Common safety rules
    creation                = each.value.rules.creation
    update                  = each.value.rules.update
    deletion                = each.value.rules.deletion
    non_fast_forward        = each.value.rules.non_fast_forward
    required_linear_history = each.value.rules.required_linear_history
    required_signatures     = each.value.rules.required_signatures

    update_allows_fetch_and_merge = each.value.rules.update_allows_fetch_and_merge

    # Pull request gates
    dynamic "pull_request" {
      for_each = each.value.rules.pull_request == null ? [] : [each.value.rules.pull_request]
      content {
        allowed_merge_methods             = pull_request.value.allowed_merge_methods
        dismiss_stale_reviews_on_push     = pull_request.value.dismiss_stale_reviews_on_push
        require_code_owner_review         = pull_request.value.require_code_owner_review
        require_last_push_approval        = pull_request.value.require_last_push_approval
        required_approving_review_count   = pull_request.value.required_approving_review_count
        required_review_thread_resolution = pull_request.value.required_review_thread_resolution
      }
    }

    # review setting
    dynamic "copilot_code_review" {
      for_each = each.value.rules.copilot_code_review == null ? [] : [each.value.rules.copilot_code_review]
      content {
        review_on_push             = copilot_code_review.value.review_on_push
        review_draft_pull_requests = copilot_code_review.value.review_draft_pull_requests
      }
    }

    # Required status checks
    dynamic "required_status_checks" {
      for_each = each.value.rules.required_status_checks == null ? [] : [each.value.rules.required_status_checks]
      content {
        do_not_enforce_on_create             = required_status_checks.value.do_not_enforce_on_create
        strict_required_status_checks_policy = required_status_checks.value.strict_required_status_checks_policy

        dynamic "required_check" {
          for_each = required_status_checks.value.required_check
          content {
            context        = required_check.value.context
            integration_id = required_check.value.integration_id
          }
        }
      }
    }

    # Required deployments (environment gates)
    dynamic "required_deployments" {
      for_each = each.value.rules.required_deployments == null ? [] : [each.value.rules.required_deployments]
      content {
        required_deployment_environments = required_deployments.value.required_deployment_environments
      }
    }

    # Required code scanning
    dynamic "required_code_scanning" {
      for_each = each.value.rules.required_code_scanning == null ? [] : [each.value.rules.required_code_scanning]
      content {
        dynamic "required_code_scanning_tool" {
          for_each = required_code_scanning.value.required_code_scanning_tool
          content {
            tool                      = required_code_scanning_tool.value.tool
            alerts_threshold          = required_code_scanning_tool.value.alerts_threshold
            security_alerts_threshold = required_code_scanning_tool.value.security_alerts_threshold
          }
        }
      }
    }

    # Merge queue
    dynamic "merge_queue" {
      for_each = each.value.rules.merge_queue == null ? [] : [each.value.rules.merge_queue]
      content {
        check_response_timeout_minutes    = merge_queue.value.check_response_timeout_minutes
        grouping_strategy                 = merge_queue.value.grouping_strategy
        max_entries_to_build              = merge_queue.value.max_entries_to_build
        max_entries_to_merge              = merge_queue.value.max_entries_to_merge
        merge_method                      = merge_queue.value.merge_method
        min_entries_to_merge              = merge_queue.value.min_entries_to_merge
        min_entries_to_merge_wait_minutes = merge_queue.value.min_entries_to_merge_wait_minutes
      }
    }

    # Pattern rules
    dynamic "branch_name_pattern" {
      for_each = each.value.rules.branch_name_pattern == null ? [] : [each.value.rules.branch_name_pattern]
      content {
        operator = branch_name_pattern.value.operator
        pattern  = branch_name_pattern.value.pattern
        name     = branch_name_pattern.value.name
        negate   = branch_name_pattern.value.negate
      }
    }

    dynamic "commit_author_email_pattern" {
      for_each = each.value.rules.commit_author_email_pattern == null ? [] : [each.value.rules.commit_author_email_pattern]
      content {
        operator = commit_author_email_pattern.value.operator
        pattern  = commit_author_email_pattern.value.pattern
        name     = commit_author_email_pattern.value.name
        negate   = commit_author_email_pattern.value.negate
      }
    }

    dynamic "committer_email_pattern" {
      for_each = each.value.rules.committer_email_pattern == null ? [] : [each.value.rules.committer_email_pattern]
      content {
        operator = committer_email_pattern.value.operator
        pattern  = committer_email_pattern.value.pattern
        name     = committer_email_pattern.value.name
        negate   = committer_email_pattern.value.negate
      }
    }

    dynamic "commit_message_pattern" {
      for_each = each.value.rules.commit_message_pattern == null ? [] : [each.value.rules.commit_message_pattern]
      content {
        operator = commit_message_pattern.value.operator
        pattern  = commit_message_pattern.value.pattern
        name     = commit_message_pattern.value.name
        negate   = commit_message_pattern.value.negate
      }
    }

    dynamic "tag_name_pattern" {
      for_each = each.value.rules.tag_name_pattern == null ? [] : [each.value.rules.tag_name_pattern]
      content {
        operator = tag_name_pattern.value.operator
        pattern  = tag_name_pattern.value.pattern
        name     = tag_name_pattern.value.name
        negate   = tag_name_pattern.value.negate
      }
    }

    # Push-target-only rules (will only render if you set them)
    dynamic "file_path_restriction" {
      for_each = each.value.rules.file_path_restriction == null ? [] : [each.value.rules.file_path_restriction]
      content {
        restricted_file_paths = file_path_restriction.value.restricted_file_paths
      }
    }

    dynamic "file_extension_restriction" {
      for_each = each.value.rules.file_extension_restriction == null ? [] : [each.value.rules.file_extension_restriction]
      content {
        restricted_file_extensions = file_extension_restriction.value.restricted_file_extensions
      }
    }

    dynamic "max_file_size" {
      for_each = each.value.rules.max_file_size == null ? [] : [each.value.rules.max_file_size]
      content {
        max_file_size = max_file_size.value.max_file_size
      }
    }

    dynamic "max_file_path_length" {
      for_each = each.value.rules.max_file_path_length == null ? [] : [each.value.rules.max_file_path_length]
      content {
        max_file_path_length = max_file_path_length.value.max_file_path_length
      }
    }
  }

  # Ordering:
  #   1. Repo exists + default branch renamed + eventual-consistency delay.
  #   2. CODEOWNERS landed on the default branch (so require_code_owner_review
  #      doesn't activate against a missing file and block the first PR).
  #   3. Then apply the ruleset.
  #
  # NOTE: github_branch.branches is intentionally ABSENT. Rulesets and
  # CODEOWNERS target the default branch, not secondary branches. A failed
  # secondary branch must not strand the repo without protections. If the
  # framework later supports non-default-branch CODEOWNERS or branch-scoped
  # (non-pattern) rulesets, this dependency list must be revisited.
  depends_on = [
    github_branch_default.default,
    time_sleep.after_branch_default,
    github_repository_file.codeowners,
  ]

  lifecycle {
    precondition {
      condition     = contains(["active", "evaluate", "disabled"], each.value.enforcement)
      error_message = "Ruleset '${each.key}' has invalid enforcement '${each.value.enforcement}'. Must be one of: active, evaluate, disabled."
    }

    # When a rule turns on require_code_owner_review, the framework must
    # either have an explicit per-repo codeowners string OR be able to
    # synthesize one (personal-account mode). If neither is true, fail
    # plan — activating the rule against a missing CODEOWNERS file would
    # block every subsequent PR in the repo.
    precondition {
      condition = (
        try(each.value.rules.pull_request.require_code_owner_review, false) == false
        || local.all_repositories[each.value.repository].effective_codeowners != null
      )
      error_message = "Ruleset '${each.key}' enables require_code_owner_review but repository '${each.value.repository}' has no effective CODEOWNERS source. Set repository.codeowners in its YAML (org mode), or set var.repo_default_codeowners, or run in personal-account mode (github_is_organization=false) to auto-synthesize."
    }
  }
}

resource "github_repository_environment" "environment" {
  for_each = local.repository_environments

  repository          = github_repository.repo[each.value.repository].name
  environment         = each.value.name
  wait_timer          = each.value.wait_timer
  can_admins_bypass   = each.value.can_admins_bypass
  prevent_self_review = each.value.prevent_self_review

  dynamic "reviewers" {
    for_each = each.value.reviewers == null ? [] : [each.value.reviewers]
    content {
      users = reviewers.value.users
      teams = reviewers.value.teams
    }
  }

  dynamic "deployment_branch_policy" {
    for_each = each.value.deployment_branch_policy == null ? [] : [each.value.deployment_branch_policy]
    content {
      protected_branches     = deployment_branch_policy.value.protected_branches
      custom_branch_policies = deployment_branch_policy.value.custom_branch_policies
    }
  }

  depends_on = [github_repository.repo]

  lifecycle {
    precondition {
      condition     = each.value.wait_timer >= 0 && each.value.wait_timer <= 43200
      error_message = "Environment '${each.key}' wait_timer must be between 0 and 43200 minutes (30 days)."
    }

    precondition {
      condition = !(
        try(each.value.deployment_branch_policy.protected_branches, false)
        && try(each.value.deployment_branch_policy.custom_branch_policies, false)
      )
      error_message = "Environment '${each.key}' cannot enable both protected_branches and custom_branch_policies in deployment_branch_policy."
    }
  }
}

resource "github_repository_environment_deployment_policy" "environment" {
  for_each = local.repository_environment_branch_policies

  repository     = github_repository.repo[each.value.repository].name
  environment    = each.value.environment
  branch_pattern = each.value.pattern

  depends_on = [github_repository_environment.environment]
}

resource "github_actions_environment_variable" "env_var" {
  for_each = local.repository_environment_variables

  repository    = github_repository.repo[each.value.repository].name
  environment   = each.value.environment
  variable_name = each.value.name
  value         = each.value.value

  depends_on = [github_repository_environment.environment]
}

resource "github_actions_environment_secret" "env_secret" {
  for_each = local.repository_environment_secrets

  repository  = github_repository.repo[each.value.repository].name
  environment = each.value.environment
  secret_name = each.value.name

  # Terraform declares the secret shell only. The real value is rotated
  # out-of-band (manual paste in GitHub UI, external rotator, etc.) and
  # ignored on subsequent plans to avoid drift / forced updates.
  plaintext_value = ""

  lifecycle {
    ignore_changes = [
      plaintext_value,
      encrypted_value,
    ]
  }

  depends_on = [github_repository_environment.environment]
}

resource "github_actions_repository_permissions" "actions" {
  for_each = {
    for name, repo in local.all_repositories :
    name => repo
    if repo.actions != null && !repo.archived
  }

  repository      = github_repository.repo[each.key].name
  enabled         = each.value.actions.enabled
  allowed_actions = each.value.actions.allowed_actions

  dynamic "allowed_actions_config" {
    for_each = each.value.actions.allowed_actions_config == null ? [] : [each.value.actions.allowed_actions_config]
    content {
      github_owned_allowed = allowed_actions_config.value.github_owned_allowed
      verified_allowed     = allowed_actions_config.value.verified_allowed
      patterns_allowed     = allowed_actions_config.value.patterns_allowed
    }
  }

  depends_on = [github_repository.repo]

  lifecycle {
    precondition {
      condition     = contains(["all", "local_only", "selected"], each.value.actions.allowed_actions)
      error_message = "Repository '${each.key}' actions.allowed_actions must be one of: all, local_only, selected."
    }

    precondition {
      condition     = each.value.actions.allowed_actions != "selected" || each.value.actions.allowed_actions_config != null
      error_message = "Repository '${each.key}' sets actions.allowed_actions='selected' but allowed_actions_config is not provided."
    }
  }
}

resource "github_repository_file" "codeowners" {
  for_each = {
    for name, repo in local.all_repositories :
    name => repo
    if repo.effective_codeowners != null && !repo.archived
  }

  repository          = github_repository.repo[each.key].name
  file                = ".github/CODEOWNERS"
  content             = each.value.effective_codeowners
  branch              = each.value.branches[0]
  commit_message      = "chore(codeowners): sync CODEOWNERS via terraform"
  commit_author       = "terraform"
  commit_email        = "terraform@users.noreply.github.com"
  overwrite_on_create = true

  # CODEOWNERS writes to the default branch (branches[0]). Secondary
  # branches are not needed — see the parallel note on
  # github_repository_ruleset.branch.depends_on above.
  depends_on = [
    github_branch_default.default,
    time_sleep.after_branch_default,
  ]
}
