#% ========================================================================================== %#
#% = File: locals.tf                                                                          %#
#% ------------------------------------------------------------------------------------------ %#
#% The locals files is where the real heavy lifting for building the working objects used by  %#
#%    resources blocks is done. within "locals", all objects defined elsewhere (i.e. data,    %#
#%    variable, etc.) processed here to prepare the object(s) for action. This file is        %#
#%    intentionally designed to be the "brain" of the plan.                                   %#
#% ========================================================================================== %#

locals {

  repo_yaml_files = sort(concat(
    tolist(fileset(path.module, "repos/public/*.yml")),
    tolist(fileset(path.module, "repos/public/*.yaml")),
    tolist(fileset(path.module, "repos/private/*.yml")),
    tolist(fileset(path.module, "repos/private/*.yaml"))
  ))

  repo_yaml_objects = [
    for f in local.repo_yaml_files :
    yamldecode(file("${path.module}/${f}"))
  ]

  # IMPORTANT: include `{}` so it works even if repo_yaml_objects is empty.
  repos_from_yaml = merge({}, local.repo_yaml_objects...)

  repo_setting_defaults = {
    has_discussions                         = false
    has_issues                              = true
    has_projects                            = false
    has_wiki                                = false
    is_template                             = false
    allow_auto_merge                        = true
    allow_merge_commit                      = false
    allow_rebase_merge                      = false
    allow_squash_merge                      = true
    allow_update_branch                     = true
    delete_branch_on_merge                  = true
    squash_merge_commit_title               = "PR_TITLE"
    squash_merge_commit_message             = "PR_BODY"
    web_commit_signoff_required             = true
    auto_init                               = true
    license_template                        = "MIT"
    archived                                = false
    archive_on_destroy                      = true
    ignore_vulnerability_alerts_during_read = false
    vulnerability_alerts                    = true
    dependabot_security_updates             = true
  }

  repo_security_defaults = {
    public = {
      advanced_security                     = null
      # Only enable the public-repo features this account/API reliably exposes.
      code_security                         = null
      secret_scanning                       = true
      secret_scanning_push_protection       = true
      secret_scanning_ai_detection          = null
      secret_scanning_non_provider_patterns = null
    }
    private = {
      # Personal-account private repos do not consistently expose the full
      # security_and_analysis feature set. Leave these unset by default and
      # opt in per repository when the backing GitHub entitlement supports it.
      advanced_security                     = null
      code_security                         = null
      secret_scanning                       = null
      secret_scanning_push_protection       = null
      secret_scanning_ai_detection          = null
      secret_scanning_non_provider_patterns = null
    }
    internal = {
      advanced_security                     = null
      code_security                         = null
      secret_scanning                       = null
      secret_scanning_push_protection       = null
      secret_scanning_ai_detection          = null
      secret_scanning_non_provider_patterns = null
    }
  }

}


locals {

  #region ------ [ LOCALS | 'all_repositories' ] --------------------------------------------- #

  all_repositories = {

    for repository_name, repository in local.repos_from_yaml : repository_name => {

      /* Required */
      name = repository_name

      /* Optional */
      branches = coalescelist(
        try(repository.branches, []),
        var.repo_default_branches
      )

      description = try(
        repository.description,
        null
      )

      homepage_url = try(
        repository.homepage_url,
        null
      )

      topics = try(
        repository.topics,
        []
      )

      #region ------ [ Forking ] ------------------------------------------------------------- #

      fork = coalesce(
        try(repository.fork, null),
        false
      )

      source_owner = (
        coalesce(try(repository.fork, null), false)
        ? try(repository.source_owner, null)
        : null
      )

      source_repo = (
        coalesce(try(repository.fork, null), false)
        ? try(repository.source_repo, null)
        : null
      )

      #endregion --- [ Forking ] ------------------------------------------------------------- #

      #region ------ [ Visibility / Features ] ----------------------------------------------- #

      has_discussions = coalesce(
        try(repository.has_discussions, null),
        local.repo_setting_defaults.has_discussions
      )

      has_issues = coalesce(
        try(repository.has_issues, null),
        local.repo_setting_defaults.has_issues
      )

      has_projects = coalesce(
        try(repository.has_projects, null),
        local.repo_setting_defaults.has_projects
      )

      has_wiki = coalesce(
        try(repository.has_wiki, null),
        local.repo_setting_defaults.has_wiki
      )

      is_template = coalesce(
        try(repository.is_template, null),
        local.repo_setting_defaults.is_template
      )

      visibility = coalesce(
        try(repository.visibility, null),
        "private"
      )

      #endregion --- [ Visibility / Features ] ----------------------------------------------- #

      #region ------ [ Merge Behavior ] ------------------------------------------------------ #

      allow_auto_merge = coalesce(
        try(repository.allow_auto_merge, null),
        local.repo_setting_defaults.allow_auto_merge
      )

      allow_forking = try(repository.allow_forking, null)

      allow_merge_commit = coalesce(
        try(repository.allow_merge_commit, null),
        local.repo_setting_defaults.allow_merge_commit
      )

      allow_rebase_merge = coalesce(
        try(repository.allow_rebase_merge, null),
        local.repo_setting_defaults.allow_rebase_merge
      )

      allow_squash_merge = coalesce(
        try(repository.allow_squash_merge, null),
        local.repo_setting_defaults.allow_squash_merge
      )

      allow_update_branch = coalesce(
        try(repository.allow_update_branch, null),
        local.repo_setting_defaults.allow_update_branch
      )

      delete_branch_on_merge = coalesce(
        try(repository.delete_branch_on_merge, null),
        local.repo_setting_defaults.delete_branch_on_merge
      )

      merge_commit_message = try(repository.merge_commit_message, null)
      merge_commit_title   = try(repository.merge_commit_title, null)
      squash_merge_commit_message = coalesce(
        try(repository.squash_merge_commit_message, null),
        local.repo_setting_defaults.squash_merge_commit_message
      )
      squash_merge_commit_title = coalesce(
        try(repository.squash_merge_commit_title, null),
        local.repo_setting_defaults.squash_merge_commit_title
      )

      web_commit_signoff_required = coalesce(
        try(repository.web_commit_signoff_required, null),
        local.repo_setting_defaults.web_commit_signoff_required
      )

      #endregion --- [ Merge Behavior ] ------------------------------------------------------ #

      #region ------ [ Initialization / Licensing ] ------------------------------------------ #

      auto_init = coalesce(
        try(repository.auto_init, null),
        local.repo_setting_defaults.auto_init
      )

      gitignore_template = try(
        repository.gitignore_template,
        null
      )

      license_template = try(
        repository.license_template,
        local.repo_setting_defaults.license_template
      )

      #endregion --- [ Initialization / Licensing ] ------------------------------------------ #

      #region ------ [ Lifecycle ] ----------------------------------------------------------- #

      archived = coalesce(
        try(repository.archived, null),
        local.repo_setting_defaults.archived
      )

      archive_on_destroy = coalesce(
        try(repository.archive_on_destroy, null),
        local.repo_setting_defaults.archive_on_destroy
      )

      #endregion --- [ Lifecycle ] ----------------------------------------------------------- #

      #region ------ [ Dependabot / Vulnerability Alerts ] ----------------------------------- #

      ignore_vulnerability_alerts_during_read = coalesce(
        try(repository.ignore_vulnerability_alerts_during_read, null),
        local.repo_setting_defaults.ignore_vulnerability_alerts_during_read
      )

      vulnerability_alerts = coalesce(
        try(repository.vulnerability_alerts, null),
        local.repo_setting_defaults.vulnerability_alerts
      )

      dependabot_security_updates = coalesce(
        try(repository.dependabot_security_updates, null),
        try(repository.vulnerability_alerts, null),
        local.repo_setting_defaults.dependabot_security_updates
      )

      #endregion --- [ Dependabot / Vulnerability Alerts ] ----------------------------------- #

      #region ------ [ Pages ] --------------------------------------------------------------- #

      pages = try(repository.pages, null) == null ? null : {
        source = try(repository.pages.source, null) == null ? null : {
          branch = repository.pages.source.branch
          path   = try(repository.pages.source.path, null)
        }
        build_type = try(repository.pages.build_type, null)
        cname      = try(repository.pages.cname)
      }

      #endregion --- [ Pages ] --------------------------------------------------------------- #

      #region ------ [ Security & Analysis ] ------------------------------------------------- #

      security_and_analysis = length([
        for setting in values(
          try(repository.security_and_analysis, null) == null ? lookup(
            local.repo_security_defaults,
            coalesce(try(repository.visibility, null), "private"),
            local.repo_security_defaults.private
          ) : merge(
            lookup(
              local.repo_security_defaults,
              coalesce(try(repository.visibility, null), "private"),
              local.repo_security_defaults.private
            ),
            repository.security_and_analysis
          )
        ) : setting if setting != null
      ]) == 0 ? null : (
        try(repository.security_and_analysis, null) == null ? lookup(
          local.repo_security_defaults,
          coalesce(try(repository.visibility, null), "private"),
          local.repo_security_defaults.private
        ) : merge(
          lookup(
            local.repo_security_defaults,
            coalesce(try(repository.visibility, null), "private"),
            local.repo_security_defaults.private
          ),
          repository.security_and_analysis
        )
      )

      #endregion --- [ Security & Analysis ] ------------------------------------------------- #

      #region ------ [ Template ] ------------------------------------------------------------ #

      template = try(repository.template, null) == null ? null : {

        owner      = repository.template.owner
        repository = repository.template.repository

        include_all_branches = coalesce(
          try(repository.template.include_all_branches, null),
          false
        )

      }

      #endregion --- [ Template ] ------------------------------------------------------------ #

      rules = try(repository.rules, null) == null ? var.repo_default_rules : repository.rules

    } #for repository
  }   #all_repositories

  #endregion --- [ LOCALS | 'all_repositories' ] --------------------------------------------- #

  #region ------ [ LOCALS | 'branches' ] ----------------------------------------------------- #

  branches = merge(
    {},
    [
      for repository in local.all_repositories : {
        for index, branch in repository.branches :
        "${repository.name}-branch-${format("%02d", index)}-${branch}" => {
          repository    = repository.name
          branch        = branch
          source_branch = index == 0 ? branch : repository.branches[index - 1]
        }

        # If rename=true, skip creating the default branch as a github_branch
        if !(
          try(local.branch_defaults[repository.name].rename, false)
          && branch == try(local.branch_defaults[repository.name].branch, "")
        )
      }

      # Don't manage branches in archived repos (and avoid empty branch lists)
      if !repository.archived && length(repository.branches) > 0

    ]... # <-- These 3 dots are intentional, it enables the merging to a flat list.
  )

  #endregion --- [ LOCALS | 'branches' ] ----------------------------------------------------- #

  #region ------ [ LOCALS | 'branch_defaults' ] ---------------------------------------------- #

  branch_defaults = {
    for repository in local.all_repositories : repository.name => {
      repository = repository.name
      branch     = repository.branches[0]
      rename     = true
    }
    if !repository.archived && length(repository.branches) > 0
  }

  #endregion --- [ LOCALS | 'branch_defaults' ] ---------------------------------------------- #

  #region ------ [ LOCALS | 'branch_rulesets' ] ---------------------------------------------- #

  branch_rulesets = merge(
    {},
    [
      for repository_name, repository in local.all_repositories : {
        for index, rule in repository.rules :
        "${repository_name}-rules-${index}" => {

          enforcement = coalesce(try(rule.enforcement, null), "active")
          name        = coalesce(try(rule.name, null), "Ruleset ${index}")
          repository  = repository_name
          target      = coalesce(try(rule.target, null), "branch")

          /* Conditions */
          exclude = try(rule.conditions.exclude, [])
          include = coalescelist(
            try(rule.conditions.include, []),
            ["~DEFAULT_BRANCH"]
          )

          bypass_actors = [
            for actor in try(rule.bypass_actors, []) : {
              actor_id   = actor.actor_id
              actor_type = actor.actor_type
              bypass_mode = coalesce(
                try(actor.bypass_mode, null),
                "always"
              )
            }
          ]

          rules = {

            creation                      = try(rule.rules.creation, null)
            deletion                      = try(rule.rules.deletion, null)
            non_fast_forward              = try(rule.rules.non_fast_forward, null)
            required_linear_history       = try(rule.rules.required_linear_history, null)
            required_signatures           = try(rule.rules.required_signatures, null)
            update                        = try(rule.rules.update, null)
            update_allows_fetch_and_merge = try(rule.rules.update_allows_fetch_and_merge, null)

            branch_name_pattern = try(rule.rules.branch_name_pattern, null) == null ? null : {
              name = try(
                rule.rules.branch_name_pattern.name,
                null
              )
              negate = coalesce(
                rule.rules.branch_name_pattern.negate,
                false
              )
              operator = coalesce(
                rule.rules.branch_name_pattern.operator,
                "regex"
              )
              pattern = coalesce(
                rule.rules.branch_name_pattern.pattern,
                "*"
              )
            }

            commit_author_email_pattern = try(rule.rules.commit_author_email_pattern, null) == null ? null : {
              name = try(
                rule.rules.commit_author_email_pattern.name,
                null
              )
              negate = coalesce(
                rule.rules.commit_author_email_pattern.negate,
                false
              )
              operator = coalesce(
                rule.rules.commit_author_email_pattern.operator,
                "regex"
              )
              pattern = coalesce(
                rule.rules.commit_author_email_pattern.pattern,
                "*"
              )
            }

            commit_message_pattern = try(rule.rules.commit_message_pattern, null) == null ? null : {
              name = try(
                rule.rules.commit_message_pattern.name,
                null
              )
              negate = coalesce(
                rule.rules.commit_message_pattern.negate,
                false
              )
              operator = coalesce(
                rule.rules.commit_message_pattern.operator,
                "regex"
              )
              pattern = coalesce(
                rule.rules.commit_message_pattern.pattern,
                "*"
              )
            }

            committer_email_pattern = try(rule.rules.committer_email_pattern, null) == null ? null : {
              name = try(
                rule.rules.committer_email_pattern.name,
                null
              )
              negate = coalesce(
                rule.rules.committer_email_pattern.negate,
                false
              )
              operator = coalesce(
                rule.rules.committer_email_pattern.operator,
                "regex"
              )
              pattern = coalesce(
                rule.rules.committer_email_pattern.pattern,
                "*"
              )
            }

            merge_queue = try(rule.rules.merge_queue, null) == null ? null : {
              /* Required */
              check_response_timeout_minutes    = rule.rules.merge_queue.check_response_timeout_minutes
              grouping_strategy                 = rule.rules.merge_queue.grouping_strategy
              max_entries_to_build              = rule.rules.merge_queue.max_entries_to_build
              max_entries_to_merge              = rule.rules.merge_queue.max_entries_to_merge
              merge_method                      = rule.rules.merge_queue.merge_method
              min_entries_to_merge              = rule.rules.merge_queue.min_entries_to_merge
              min_entries_to_merge_wait_minutes = rule.rules.merge_queue.min_entries_to_merge_wait_minutes
            }

            pull_request = try(rule.rules.pull_request, null) == null ? null : {
              allowed_merge_methods = coalesce(
                rule.rules.pull_request.allowed_merge_methods,
                ["merge", "squash"]
              )
              dismiss_stale_reviews_on_push = coalesce(
                rule.rules.pull_request.dismiss_stale_reviews_on_push,
                true
              )
              require_code_owner_review = coalesce(
                rule.rules.pull_request.require_code_owner_review,
                false
              )
              require_last_push_approval = coalesce(
                rule.rules.pull_request.require_last_push_approval,
                false
              )
              required_approving_review_count = coalesce(
                rule.rules.pull_request.required_approving_review_count,
                1
              )
              required_review_thread_resolution = coalesce(
                rule.rules.pull_request.required_review_thread_resolution,
                false
              )
            }

            copilot_code_review = try(rule.rules.copilot_code_review, null) == null ? null : {
              review_on_push = coalesce(
                rule.rules.copilot_code_review.review_on_push,
                false
              )
              review_draft_pull_requests = coalesce(
                rule.rules.copilot_code_review.review_draft_pull_requests,
                false
              )
            }

            required_deployments = try(rule.rules.required_deployments, null) == null ? null : {
              required_deployment_environments = rule.rules.required_deployments.required_deployment_environments
            }

            required_status_checks = try(rule.rules.required_status_checks, null) == null ? null : {
              required_check = [
                for required_check in try(rule.rules.required_status_checks.required_check, []) : {
                  context        = required_check.context
                  integration_id = try(required_check.integration_id, null)
                }
              ]
              strict_required_status_checks_policy = coalesce(
                rule.rules.required_status_checks.strict_required_status_checks_policy,
                false
              )
              do_not_enforce_on_create = coalesce(
                rule.rules.required_status_checks.do_not_enforce_on_create,
                false
              )
            }

            tag_name_pattern = try(rule.rules.tag_name_pattern, null) == null ? null : {
              name = try(
                rule.rules.tag_name_pattern.name,
                null
              )
              negate = coalesce(
                rule.rules.tag_name_pattern.negate,
                false
              )
              operator = coalesce(
                rule.rules.tag_name_pattern.operator,
                "regex"
              )
              pattern = coalesce(
                rule.rules.tag_name_pattern.pattern,
                "*"
              )
            }

            required_code_scanning = try(rule.rules.required_code_scanning, null) == null ? null : {
              required_code_scanning_tool = [
                for required_code_scanning_tool in rule.rules.required_code_scanning.required_code_scanning_tool : {
                  tool = required_code_scanning_tool.tool
                  alerts_threshold = coalesce(
                    required_code_scanning_tool.alerts_threshold,
                    "high_or_higher"
                  )
                  security_alerts_threshold = coalesce(
                    required_code_scanning_tool.security_alerts_threshold,
                    "high_or_higher"
                  )
                }
              ]
            }

            file_path_restriction = try(rule.rules.file_path_restriction, null) == null ? null : {
              restricted_file_paths = rule.rules.file_path_restriction.restricted_file_paths
            }

            max_file_size = try(rule.rules.max_file_size, null) == null ? null : {
              max_file_size = coalesce(
                rule.rules.max_file_size.max_file_size,
                1
              )
            }

            # This rule only applies to rulesets with target push.
            max_file_path_length = try(rule.rules.max_file_path_length, null) == null ? null : {
              max_file_path_length = coalesce(
                rule.rules.max_file_path_length.max_file_path_length,
                255
              )
            }

            # This rule only applies to rulesets with target push.
            file_extension_restriction = try(rule.rules.file_extension_restriction, null) == null ? null : {
              restricted_file_extensions = rule.rules.file_extension_restriction.restricted_file_extensions
            }
          }
        }

        # Only generate rulesets if the repository defines them
        if length(repository.rules) > 0 && (
          coalesce(try(rule.target, null), "branch") != "push"
          || (
            var.github_supports_push_rulesets
            && contains(["private", "internal"], repository.visibility)
          )
        )
      }

      # Skip archived repos
      if !repository.archived
    ]...
  )

  #endregion --- [ LOCALS | 'branch_rulesets' ] ---------------------------------------------- #

}

#% ========================================================================================== %#
#% Input Validation Checks                                                                     %#
#% ========================================================================================== %#

check "validate_repo_visibility" {
  assert {
    condition = alltrue([
      for name, repo in local.all_repositories :
      contains(["public", "private", "internal"], repo.visibility)
    ])
    error_message = "All repository visibility values must be one of: public, private, internal."
  }
}

check "validate_ruleset_enforcement" {
  assert {
    condition = alltrue([
      for key, ruleset in local.branch_rulesets :
      contains(["active", "evaluate", "disabled"], ruleset.enforcement)
    ])
    error_message = "All ruleset enforcement values must be one of: active, evaluate, disabled."
  }
}

check "validate_public_repos_have_description" {
  assert {
    condition = alltrue([
      for name, repo in local.all_repositories :
      repo.description != null && repo.description != ""
      if repo.visibility == "public"
    ])
    error_message = "All public repositories must have a description (DESIGN.md Section 2.2)."
  }
}
