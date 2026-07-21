#% ========================================================================================== %#
#% = File: 30-locals.tf                                                                       %#
#% ------------------------------------------------------------------------------------------ %#
#% The locals files is where the real heavy lifting for building the working objects used by  %#
#%    resources blocks is done. within "locals", all objects defined elsewhere (i.e. data,    %#
#%    variable, etc.) processed here to prepare the object(s) for action. This file is        %#
#%    intentionally designed to be the "brain" of the plan.                                   %#
#% ========================================================================================== %#

locals {

  # Empty or whitespace-only global CODEOWNERS content is treated as unset.
  _default_codeowners = try(trimspace(var.repo_default_codeowners), "") != "" ? var.repo_default_codeowners : null

  repo_yaml_files = sort(concat(
    tolist(fileset(path.module, "${var.repo_yaml_path}/public/*.yml")),
    tolist(fileset(path.module, "${var.repo_yaml_path}/public/*.yaml")),
    tolist(fileset(path.module, "${var.repo_yaml_path}/private/*.yml")),
    tolist(fileset(path.module, "${var.repo_yaml_path}/private/*.yaml"))
  ))

  repo_yaml_objects = [
    for f in local.repo_yaml_files :
    yamldecode(file("${path.module}/${f}"))
  ]

  # IMPORTANT: include `{}` so it works even if repo_yaml_objects is empty.
  repos_from_yaml = merge({}, local.repo_yaml_objects...)

  # Total repo-key occurrences across all YAML files. Compared against
  # length(repos_from_yaml) by a precondition to detect duplicate definitions
  # (which merge() would silently collapse).
  repo_yaml_key_count = sum(concat([0], [
    for o in local.repo_yaml_objects : length(keys(o))
  ]))

  # Known top-level keys accepted in a repository YAML document. Any key
  # outside this set indicates a typo or schema drift and is rejected by
  # terraform_data.framework_validation.
  #
  # NOTE: `allow_forking` defaults by visibility and ownership: true for
  # public, false for internal and organization-owned private, and null
  # for personal-account private repositories so the provider omits the
  # field. Explicit YAML values pass through, except public false is
  # rejected because public forking is not restrictable on github.com.
  # UNVERIFIED: does the GitHub API accept an explicit allow_forking on personal-account private repos? Needs a live 1-repo test.
  allowed_repo_keys = toset([
    "description", "homepage_url", "topics",
    "fork", "source_owner", "source_repo",
    "visibility", "has_discussions", "has_issues", "has_projects", "has_wiki", "is_template",
    "allow_auto_merge", "allow_forking", "allow_merge_commit", "allow_rebase_merge",
    "allow_squash_merge", "allow_update_branch", "delete_branch_on_merge",
    "merge_commit_message", "merge_commit_title",
    "squash_merge_commit_message", "squash_merge_commit_title",
    "web_commit_signoff_required",
    "auto_init", "gitignore_template", "license_template",
    "archived", "archive_on_destroy",
    "vulnerability_alerts",
    "pages", "security_and_analysis", "unmanaged_security_features", "template",
    "branches", "rules", "actions", "environments",
    "codeowners", "required_checks",
  ])

  # Allowed keys for nested object types. These are checked in addition to
  # the top-level repo key set so a typo like `actions.allowd_actions` or
  # `rules[].rules.pull_reqeust` is rejected rather than silently defaulted.
  allowed_pages_keys                  = toset(["source", "build_type", "cname"])
  allowed_pages_source_keys           = toset(["branch", "path"])
  allowed_template_keys               = toset(["owner", "repository", "include_all_branches"])
  allowed_security_and_analysis_keys  = toset(["advanced_security", "code_security", "secret_scanning", "secret_scanning_push_protection", "secret_scanning_ai_detection", "secret_scanning_non_provider_patterns"])
  allowed_actions_keys                = toset(["enabled", "allowed_actions", "allowed_actions_config"])
  allowed_actions_config_keys         = toset(["github_owned_allowed", "verified_allowed", "patterns_allowed"])
  allowed_environment_keys            = toset(["wait_timer", "can_admins_bypass", "prevent_self_review", "reviewers", "deployment_branch_policy", "branch_policies", "variables", "secrets"])
  allowed_environment_reviewers_keys  = toset(["users", "teams"])
  allowed_environment_dbp_keys        = toset(["protected_branches", "custom_branch_policies"])
  allowed_rule_keys                   = toset(["name", "target", "enforcement", "bypass_actors", "conditions", "rules"])
  allowed_rule_conditions_keys        = toset(["include", "exclude"])
  allowed_rule_bypass_actor_keys      = toset(["actor_id", "actor_type", "bypass_mode"])
  allowed_rule_rules_keys             = toset(["creation", "update", "deletion", "non_fast_forward", "required_linear_history", "required_signatures", "update_allows_fetch_and_merge", "pull_request", "copilot_code_review", "required_status_checks", "required_deployments", "required_code_scanning", "merge_queue", "branch_name_pattern", "commit_author_email_pattern", "committer_email_pattern", "commit_message_pattern", "tag_name_pattern", "file_path_restriction", "file_extension_restriction", "max_file_size", "max_file_path_length"])
  allowed_pull_request_keys           = toset(["allowed_merge_methods", "dismiss_stale_reviews_on_push", "require_code_owner_review", "require_last_push_approval", "required_approving_review_count", "required_review_thread_resolution"])
  allowed_merge_queue_keys            = toset(["check_response_timeout_minutes", "grouping_strategy", "max_entries_to_build", "max_entries_to_merge", "merge_method", "min_entries_to_merge", "min_entries_to_merge_wait_minutes"])
  allowed_copilot_code_review_keys    = toset(["review_on_push", "review_draft_pull_requests"])
  allowed_required_status_checks_keys = toset(["required_check", "do_not_enforce_on_create", "strict_required_status_checks_policy"])
  allowed_pattern_block_keys          = toset(["operator", "pattern", "name", "negate"])
  allowed_code_scanning_tool_keys     = toset(["tool", "alerts_threshold", "security_alerts_threshold"])

  repos_with_unknown_keys = {
    for name, repo in local.repos_from_yaml :
    name => setsubtract(keys(repo), local.allowed_repo_keys)
    if length(setsubtract(keys(repo), local.allowed_repo_keys)) > 0
  }

  repo_setting_defaults = {
    has_discussions             = false
    has_issues                  = true
    has_projects                = false
    has_wiki                    = false
    is_template                 = false
    allow_auto_merge            = true
    allow_merge_commit          = false
    allow_rebase_merge          = false
    allow_squash_merge          = true
    allow_update_branch         = true
    delete_branch_on_merge      = true
    squash_merge_commit_title   = "PR_TITLE"
    squash_merge_commit_message = "PR_BODY"
    # Omit at the repo level: web_commit_signoff is ORG-ENFORCED (org_settings), and
    # GitHub 422s any repo-level write of it once enforced ("cannot be disabled").
    # null => the attribute is omitted, so the org setting is the single source of
    # truth. A repo's YAML may still explicitly set it to override.
    web_commit_signoff_required = null
    auto_init                   = true
    license_template            = null
    archived                    = false
    archive_on_destroy          = true
    vulnerability_alerts        = false
  }

  # Names of every feature in the security capability / baseline matrix.
  # Iterating this set lets capability-aware normalization stay data-driven
  # instead of repeating every field by name.
  security_features = toset([
    "advanced_security",
    "code_security",
    "secret_scanning",
    "secret_scanning_push_protection",
    "secret_scanning_ai_detection",
    "secret_scanning_non_provider_patterns",
  ])

}

#% ========================================================================================== %#
#% Global validation error aggregation.                                                        %#
#% ------------------------------------------------------------------------------------------ %#
#% These locals walk the decoded YAML and produce a flat list of error strings. The list is    %#
#% consumed by terraform_data.framework_validation (see 41-resources-github.tf), whose          %#
#% precondition fails plan when the list is non-empty. Per-resource checks (visibility,        %#
#% ruleset enforcement, env wait_timer, etc.) stay on their respective resources so error      %#
#% messages point at specific resource addresses.                                              %#
#% ========================================================================================== %#
locals {

  duplicate_key_error = (
    local.repo_yaml_key_count == length(local.repos_from_yaml)
    ? []
    : ["Duplicate repository keys detected across repos/public and repos/private YAML files. merge() silently collapses duplicates, so at least one repository definition was lost. Find and remove the duplicate before applying."]
  )

  unknown_top_level_key_errors = [
    for name, unknown in local.repos_with_unknown_keys :
    "Repository '${name}': unknown top-level YAML key(s): ${jsonencode(unknown)}. Allowed keys: ${jsonencode(tolist(local.allowed_repo_keys))}."
  ]

  unknown_nested_key_errors = flatten([
    for name, repo in local.repos_from_yaml : concat(
      # pages
      try(repo.pages, null) == null ? [] : [
        for k in setsubtract(keys(repo.pages), local.allowed_pages_keys) :
        "Repository '${name}' pages: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_pages_keys))}."
      ],
      try(repo.pages.source, null) == null ? [] : [
        for k in setsubtract(keys(repo.pages.source), local.allowed_pages_source_keys) :
        "Repository '${name}' pages.source: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_pages_source_keys))}."
      ],
      # template
      try(repo.template, null) == null ? [] : [
        for k in setsubtract(keys(repo.template), local.allowed_template_keys) :
        "Repository '${name}' template: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_template_keys))}."
      ],
      # security_and_analysis
      try(repo.security_and_analysis, null) == null ? [] : [
        for k in setsubtract(keys(repo.security_and_analysis), local.allowed_security_and_analysis_keys) :
        "Repository '${name}' security_and_analysis: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_security_and_analysis_keys))}."
      ],
      # actions
      try(repo.actions, null) == null ? [] : [
        for k in setsubtract(keys(repo.actions), local.allowed_actions_keys) :
        "Repository '${name}' actions: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_actions_keys))}."
      ],
      try(repo.actions.allowed_actions_config, null) == null ? [] : [
        for k in setsubtract(keys(repo.actions.allowed_actions_config), local.allowed_actions_config_keys) :
        "Repository '${name}' actions.allowed_actions_config: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_actions_config_keys))}."
      ],
      # environments
      flatten([
        for env_name, env in try(repo.environments, {}) : [
          for k in setsubtract(keys(env), local.allowed_environment_keys) :
          "Repository '${name}' environments['${env_name}']: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_environment_keys))}."
        ]
      ]),
      flatten([
        for env_name, env in try(repo.environments, {}) :
        try(env.reviewers, null) == null ? [] : [
          for k in setsubtract(keys(env.reviewers), local.allowed_environment_reviewers_keys) :
          "Repository '${name}' environments['${env_name}'].reviewers: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_environment_reviewers_keys))}."
        ]
      ]),
      flatten([
        for env_name, env in try(repo.environments, {}) :
        try(env.deployment_branch_policy, null) == null ? [] : [
          for k in setsubtract(keys(env.deployment_branch_policy), local.allowed_environment_dbp_keys) :
          "Repository '${name}' environments['${env_name}'].deployment_branch_policy: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_environment_dbp_keys))}."
        ]
      ]),
      # rules (list)
      flatten([
        for idx, rule in try(repo.rules, []) : [
          for k in setsubtract(keys(rule), local.allowed_rule_keys) :
          "Repository '${name}' rules[${idx}]: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_rule_keys))}."
        ]
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) :
        try(rule.conditions, null) == null ? [] : [
          for k in setsubtract(keys(rule.conditions), local.allowed_rule_conditions_keys) :
          "Repository '${name}' rules[${idx}].conditions: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_rule_conditions_keys))}."
        ]
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) : flatten([
          for actor_idx, actor in try(rule.bypass_actors, []) : [
            for k in setsubtract(keys(actor), local.allowed_rule_bypass_actor_keys) :
            "Repository '${name}' rules[${idx}].bypass_actors[${actor_idx}]: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_rule_bypass_actor_keys))}."
          ]
        ])
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) :
        try(rule.rules, null) == null ? [] : [
          for k in setsubtract(keys(rule.rules), local.allowed_rule_rules_keys) :
          "Repository '${name}' rules[${idx}].rules: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_rule_rules_keys))}."
        ]
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) :
        try(rule.rules.pull_request, null) == null ? [] : [
          for k in setsubtract(keys(rule.rules.pull_request), local.allowed_pull_request_keys) :
          "Repository '${name}' rules[${idx}].rules.pull_request: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_pull_request_keys))}."
        ]
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) :
        try(rule.rules.merge_queue, null) == null ? [] : [
          for k in setsubtract(keys(rule.rules.merge_queue), local.allowed_merge_queue_keys) :
          "Repository '${name}' rules[${idx}].rules.merge_queue: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_merge_queue_keys))}."
        ]
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) :
        try(rule.rules.copilot_code_review, null) == null ? [] : [
          for k in setsubtract(keys(rule.rules.copilot_code_review), local.allowed_copilot_code_review_keys) :
          "Repository '${name}' rules[${idx}].rules.copilot_code_review: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_copilot_code_review_keys))}."
        ]
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) :
        try(rule.rules.required_status_checks, null) == null ? [] : [
          for k in setsubtract(keys(rule.rules.required_status_checks), local.allowed_required_status_checks_keys) :
          "Repository '${name}' rules[${idx}].rules.required_status_checks: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_required_status_checks_keys))}."
        ]
      ]),
      flatten([
        for idx, rule in try(repo.rules, []) : flatten([
          for pb in ["branch_name_pattern", "commit_author_email_pattern", "committer_email_pattern", "commit_message_pattern", "tag_name_pattern"] :
          try(rule.rules[pb], null) == null ? [] : [
            for k in setsubtract(keys(rule.rules[pb]), local.allowed_pattern_block_keys) :
            "Repository '${name}' rules[${idx}].rules.${pb}: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_pattern_block_keys))}."
          ]
        ])
      ]),
      # required_code_scanning.required_code_scanning_tool[] — multi-field,
      # a typo like 'alert_threshold' silently defaults via coalesce(try()).
      flatten([
        for idx, rule in try(repo.rules, []) :
        try(rule.rules.required_code_scanning, null) == null ? [] : flatten([
          for tool_idx, tool in try(rule.rules.required_code_scanning.required_code_scanning_tool, []) : [
            for k in setsubtract(keys(tool), local.allowed_code_scanning_tool_keys) :
            "Repository '${name}' rules[${idx}].rules.required_code_scanning.required_code_scanning_tool[${tool_idx}]: unknown key '${k}'. Allowed: ${jsonencode(tolist(local.allowed_code_scanning_tool_keys))}."
          ]
        ])
      ]),
    )
  ])

  # Push rulesets requested on owners/visibilities that do not support them.
  # The previous behavior silently dropped these from branch_rulesets; now
  # they are a plan-blocking validation error (Finding 3).
  unsupported_push_ruleset_errors = flatten([
    for name, repo in local.repos_from_yaml : [
      for idx, rule in try(repo.rules, []) :
      "Repository '${name}' rules[${idx}] requests target='push', but push rulesets are not supported for this owner/plan/visibility combination (visibility='${coalesce(try(repo.visibility, null), "private")}', github_supports_push_rulesets=${var.github_supports_push_rulesets}). Push rulesets require a Team-plan-or-higher owner AND a private/internal repository."
      if coalesce(try(rule.target, null), "branch") == "push" && !(
        var.github_supports_push_rulesets && contains(["private", "internal"], coalesce(try(repo.visibility, null), "private"))
      )
    ]
  ])

  # Authentication mode must have exactly one matching credential source.
  auth_config_errors = concat(
    var.github_auth_mode == "token" && var.github_token == null ? ["github_auth_mode='token' but var.github_token is null. Provide a PAT or switch to app mode."] : [],
    var.github_auth_mode == "app" && var.github_app_auth == null ? ["github_auth_mode='app' but var.github_app_auth is null. Provide GitHub App credentials or switch to token mode."] : [],
    var.github_auth_mode == "token" && var.github_app_auth != null ? ["github_auth_mode='token' but var.github_app_auth is also set. Exactly one auth source must be configured."] : [],
    var.github_auth_mode == "app" && var.github_token != null ? ["github_auth_mode='app' but var.github_token is also set. Exactly one auth source must be configured."] : [],
  )

  # Strict security baseline: a feature requested in var.security_baseline for
  # a visibility the framework will actually touch, but not supported per
  # var.github_security_capabilities, is a plan-blocking error. In
  # compatibility mode this list is populated for preview via a check block
  # but does NOT block plan — that is the one intentional use of a check
  # block in this framework (see plan Finding 4 exception).
  security_capability_gap_preview = flatten([
    for vis in ["public", "private", "internal"] : [
      for feat in local.security_features :
      "Visibility '${vis}' requires security feature '${feat}' per var.security_baseline, but var.github_security_capabilities.${vis}.${feat} = false. Either declare the capability or remove the baseline requirement."
      if var.security_baseline[vis][feat] && !var.github_security_capabilities[vis][feat]
    ]
  ])

  security_capability_gap_errors = (
    var.security_baseline_mode == "strict" ? local.security_capability_gap_preview : []
  )

  unmanaged_security_feature_errors = flatten([
    for name, repo in local.repos_from_yaml :
    try(repo.unmanaged_security_features, null) == null ? [] : [
      for feat in setsubtract(toset(repo.unmanaged_security_features), local.security_features) :
      "Repository '${name}' unmanaged_security_features: unknown feature '${feat}'. Allowed: ${jsonencode(tolist(local.security_features))}."
    ]
  ])

  security_pin_exclude_errors = [
    for feat in setsubtract(toset(var.security_pin_exclude), local.security_features) :
    "security_pin_exclude: unknown feature '${feat}'. Allowed: ${jsonencode(tolist(local.security_features))}."
  ]

  # Guard against someone writing secrets as a key-value map instead of a
  # list of names. YAML map form (`SECRET_NAME: "value"`) would commit
  # secret material to the repo in plaintext — the framework must reject
  # this shape before plan succeeds.
  secrets_type_errors = flatten([
    for name, repo in local.repos_from_yaml : [
      for env_name, env in try(repo.environments, {}) :
      "Repository '${name}' environments['${env_name}'].secrets must be a list of secret names (strings), not a key-value map. Do not put secret values in YAML — they would be committed to git in plaintext. Use the list form:\n  secrets:\n    - SECRET_NAME_A\n    - SECRET_NAME_B"
      if try(env.secrets, null) != null && !can(tolist(env.secrets))
    ]
  ])

  organization_settings = var.org_settings == null ? null : {
    name                                                         = var.org_settings.name
    description                                                  = var.org_settings.description
    company                                                      = var.org_settings.company
    blog                                                         = var.org_settings.blog
    email                                                        = var.org_settings.email
    location                                                     = var.org_settings.location
    twitter_username                                             = var.org_settings.twitter_username
    default_repository_permission                                = var.org_settings.default_repository_permission
    members_can_create_repositories                              = var.org_settings.members_can_create_repositories
    members_can_create_public_repositories                       = var.org_settings.members_can_create_public_repositories
    members_can_create_private_repositories                      = var.org_settings.members_can_create_private_repositories
    members_can_create_internal_repositories                     = var.org_settings.members_can_create_internal_repositories
    members_can_create_pages                                     = var.org_settings.members_can_create_pages
    members_can_create_public_pages                              = var.org_settings.members_can_create_public_pages
    members_can_create_private_pages                             = var.org_settings.members_can_create_private_pages
    members_can_fork_private_repositories                        = var.org_settings.members_can_fork_private_repositories
    has_organization_projects                                    = var.org_settings.has_organization_projects
    has_repository_projects                                      = var.org_settings.has_repository_projects
    web_commit_signoff_required                                  = var.org_settings.web_commit_signoff_required
    advanced_security_enabled_for_new_repositories               = var.org_settings.security_defaults_for_new_repositories.advanced_security
    secret_scanning_enabled_for_new_repositories                 = var.org_settings.security_defaults_for_new_repositories.secret_scanning
    secret_scanning_push_protection_enabled_for_new_repositories = var.org_settings.security_defaults_for_new_repositories.secret_scanning_push_protection
    dependabot_alerts_enabled_for_new_repositories               = var.org_settings.security_defaults_for_new_repositories.dependabot_alerts
    dependabot_security_updates_enabled_for_new_repositories     = var.org_settings.security_defaults_for_new_repositories.dependabot_security_updates
    dependency_graph_enabled_for_new_repositories                = var.org_settings.security_defaults_for_new_repositories.dependency_graph
  }

  org_settings_owner_errors = (
    var.org_settings != null && !var.github_is_organization
    ? ["org settings require an organization owner (github_is_organization = true). Personal accounts have no org surface."]
    : []
  )

  org_settings_name_errors = (
    var.org_settings != null && try(trimspace(var.org_settings.name), "") == ""
    ? ["org_settings.name must be a non-empty display name. An empty string would wipe the organization's display name via the whole-object PATCH."]
    : []
  )

  public_forking_errors = [
    for name, repo in local.repos_from_yaml :
    "Repository '${name}' is public and explicitly sets allow_forking=false; public forking is not restrictable on github.com, so this would cause a 422 or permanent diff."
    if coalesce(try(repo.visibility, null), "private") == "public" ? try(repo.allow_forking, null) == false : false
  ]

  global_validation_errors = concat(
    local.duplicate_key_error,
    local.unknown_top_level_key_errors,
    local.unknown_nested_key_errors,
    local.unsupported_push_ruleset_errors,
    local.auth_config_errors,
    local.security_capability_gap_errors,
    local.unmanaged_security_feature_errors,
    local.security_pin_exclude_errors,
    local.secrets_type_errors,
    local.org_settings_owner_errors,
    local.org_settings_name_errors,
    local.public_forking_errors,
  )
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

      # Default policy (visibility- and ownership-aware): explicit YAML
      # wins; otherwise public is true, internal and organization-owned
      # private are false, and personal-account private is null so the
      # provider omits the field. Public false is rejected upstream.
      # UNVERIFIED: does the GitHub API accept an explicit allow_forking on personal-account private repos? Needs a live 1-repo test.
      allow_forking = (
        try(repository.allow_forking, null) != null
        ? repository.allow_forking
        : (
          coalesce(try(repository.visibility, null), "private") == "public" ? true :
          coalesce(try(repository.visibility, null), "private") == "internal" ? false :
          var.github_is_organization ? false : null
        )
      )

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

      # web_commit_signoff is ORG-ENFORCED when org_settings sets it true: GitHub
      # then 422s ANY repo-level write of the attribute ("cannot be disabled"), so
      # when the org enforces it the repo value MUST be null (omit) regardless of
      # YAML. When the org does NOT enforce it, respect the repo level: the repo's
      # YAML value if set, else the null default (still omit). try (not coalesce)
      # because the default is null and coalesce rejects an all-null argument list.
      # try(...) on the org read: local.organization_settings is null in personal
      # mode (no org enforcement), in which case we respect the repo level.
      web_commit_signoff_required = (
        try(local.organization_settings.web_commit_signoff_required, false)
        ? null
        : try(repository.web_commit_signoff_required, local.repo_setting_defaults.web_commit_signoff_required)
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

      vulnerability_alerts = coalesce(
        try(repository.vulnerability_alerts, null),
        local.repo_setting_defaults.vulnerability_alerts
      )

      #endregion --- [ Dependabot / Vulnerability Alerts ] ----------------------------------- #

      #region ------ [ Pages ] --------------------------------------------------------------- #

      pages = try(repository.pages, null) == null ? null : {
        source = try(repository.pages.source, null) == null ? null : {
          branch = try(repository.pages.source.branch, null)
          path   = try(repository.pages.source.path, null)
        }
        build_type = try(repository.pages.build_type, null)
        cname      = try(repository.pages.cname, null)
      }

      #endregion --- [ Pages ] --------------------------------------------------------------- #

      #region ------ [ Security & Analysis ] ------------------------------------------------- #

      # Capability-aware security_and_analysis normalization.
      #
      # Precedence: unmanaged, fleet pin exclusion, explicit YAML, enabled
      # baseline, then disabled(false) or unmanaged(null) fallback. Capabilities
      # gate ONLY the baseline path; explicit YAML true intentionally bypasses
      # capability=false as the sanctioned, reviewed opt-in.
      #
      # In 'strict' mode, a baseline-vs-capability mismatch is already
      # reported as a plan-blocking global validation error, so by the time
      # this expression runs the capability check is just a guard.
      security_and_analysis = (
        # Guard: if visibility is not a known key in the baseline/capability
        # matrices (e.g., a typo like "bogus"), skip security normalization
        # entirely — the per-resource precondition on visibility enum will
        # reject the plan before any resource is created.
        !contains(["public", "private", "internal"], coalesce(try(repository.visibility, null), "private"))
        ? null
        : length([
          for feat in local.security_features :
          feat if(
            contains(try(repository.unmanaged_security_features, []), feat) ? null :
            contains(var.security_pin_exclude, feat) ? null :
            try(repository.security_and_analysis[feat], null) != null ? repository.security_and_analysis[feat] :
            var.security_baseline[coalesce(try(repository.visibility, null), "private")][feat] && var.github_security_capabilities[coalesce(try(repository.visibility, null), "private")][feat] ? true :
            var.security_default_status == "disabled" ? false : null
          ) != null
          ]) == 0 ? null : {
          for feat in local.security_features : feat => (
            contains(try(repository.unmanaged_security_features, []), feat)
            ? null
            : contains(var.security_pin_exclude, feat)
            ? null
            : (
              try(repository.security_and_analysis[feat], null) != null
              ? repository.security_and_analysis[feat]
              : (
                var.security_baseline[coalesce(try(repository.visibility, null), "private")][feat]
                && var.github_security_capabilities[coalesce(try(repository.visibility, null), "private")][feat]
                ? true
                : (var.security_default_status == "disabled" ? false : null)
              )
            )
          )
        }
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

      rules = try(repository.rules, var.repo_default_rules)

      # Opt-in required status checks. When a repo lists check contexts here,
      # they are injected into its Pull Request Gate ruleset (the ruleset that
      # carries a pull_request rule) as a required_status_checks rule. Empty
      # (the default) means no change — CI stays advisory, as before.
      required_checks = try(repository.required_checks, [])

      # Effective CODEOWNERS resolution.
      #
      # Precedence:
      #   1. Explicit repo.codeowners in YAML — the operator override in both modes.
      #   2. Non-empty global repo_default_codeowners — honored in both modes.
      #   3. Personal-account mode — synthesize '* @<owner>\n'.
      #   4. Org mode with neither source — null; the ruleset precondition guards
      #      repositories that require code-owner review.
      codeowners = try(repository.codeowners, null)

      effective_codeowners = (
        try(repository.codeowners, null) != null
        ? repository.codeowners
        : local._default_codeowners != null
        ? local._default_codeowners
        : !var.github_is_organization
        ? "* @${var.github_owner}\n"
        : null
      )

      #region ------ [ Actions Permissions ] ------------------------------------------------- #

      actions = try(repository.actions, null) == null ? null : {
        enabled = coalesce(
          try(repository.actions.enabled, null),
          true
        )
        allowed_actions = coalesce(
          try(repository.actions.allowed_actions, null),
          "all"
        )
        allowed_actions_config = try(repository.actions.allowed_actions_config, null) == null ? null : {
          github_owned_allowed = coalesce(
            try(repository.actions.allowed_actions_config.github_owned_allowed, null),
            true
          )
          # Default FALSE (fail-closed). `verified_allowed` permits any Marketplace
          # action from a GitHub-verified creator, and there is NO supported API
          # that resolves whether a given action would qualify — so a repo relying
          # on it has an allow surface that cannot be statically proven. Defaulting
          # true silently granted that surface to every `selected` repo. With false,
          # coverage is decidable from same-owner / github-owned / patterns_allowed,
          # and any genuine need becomes an explicit, reviewable pattern.
          #
          # Inert at introduction: this default only applies when a repo declares
          # allowed_actions_config but OMITS verified_allowed. Verified 2026-07-20
          # across all 21 repos (20 public YAMLs + the 1 S3-only private def): zero
          # such repos exist, so this changes no live policy — it is a contract for
          # future onboarding.
          verified_allowed = coalesce(
            try(repository.actions.allowed_actions_config.verified_allowed, null),
            false
          )
          patterns_allowed = try(
            repository.actions.allowed_actions_config.patterns_allowed,
            []
          )
        }
      }

      #endregion --- [ Actions Permissions ] ------------------------------------------------- #

      #region ------ [ Environments ] -------------------------------------------------------- #

      environments = {
        for env_name, env in try(repository.environments, {}) : env_name => {
          name = env_name

          wait_timer = coalesce(
            try(env.wait_timer, null),
            0
          )

          can_admins_bypass = coalesce(
            try(env.can_admins_bypass, null),
            true
          )

          prevent_self_review = coalesce(
            try(env.prevent_self_review, null),
            false
          )

          reviewers = try(env.reviewers, null) == null ? null : {
            users = try(env.reviewers.users, [])
            teams = try(env.reviewers.teams, [])
          }

          deployment_branch_policy = try(env.deployment_branch_policy, null) == null ? null : {
            protected_branches = coalesce(
              try(env.deployment_branch_policy.protected_branches, null),
              false
            )
            custom_branch_policies = coalesce(
              try(env.deployment_branch_policy.custom_branch_policies, null),
              false
            )
          }

          branch_policies = try(env.branch_policies, [])

          # Plaintext variables defined directly in YAML.
          variables = try(env.variables, {})

          # Secret NAMES declared in YAML. Terraform creates the secret shell
          # with an empty value and ignores all subsequent value changes, so
          # the actual secret material is rotated out-of-band (manual paste,
          # external rotator, CI bootstrap script, etc.) without causing drift.
          secrets = try(env.secrets, [])
        }
      }

      #endregion --- [ Environments ] -------------------------------------------------------- #

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
          repository = repository.name
          branch     = branch
          # All non-default branches source from the (renamed) default branch.
          # This avoids a serial dependency chain across the branch list, so
          # one failure doesn't cascade and branches can create in parallel.
          source_branch = repository.branches[0]
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
              actor_id   = try(actor.actor_id, null)
              actor_type = try(actor.actor_type, null)
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
              name     = try(rule.rules.branch_name_pattern.name, null)
              negate   = coalesce(try(rule.rules.branch_name_pattern.negate, null), false)
              operator = coalesce(try(rule.rules.branch_name_pattern.operator, null), "regex")
              pattern  = coalesce(try(rule.rules.branch_name_pattern.pattern, null), "*")
            }

            commit_author_email_pattern = try(rule.rules.commit_author_email_pattern, null) == null ? null : {
              name     = try(rule.rules.commit_author_email_pattern.name, null)
              negate   = coalesce(try(rule.rules.commit_author_email_pattern.negate, null), false)
              operator = coalesce(try(rule.rules.commit_author_email_pattern.operator, null), "regex")
              pattern  = coalesce(try(rule.rules.commit_author_email_pattern.pattern, null), "*")
            }

            commit_message_pattern = try(rule.rules.commit_message_pattern, null) == null ? null : {
              name     = try(rule.rules.commit_message_pattern.name, null)
              negate   = coalesce(try(rule.rules.commit_message_pattern.negate, null), false)
              operator = coalesce(try(rule.rules.commit_message_pattern.operator, null), "regex")
              pattern  = coalesce(try(rule.rules.commit_message_pattern.pattern, null), "*")
            }

            committer_email_pattern = try(rule.rules.committer_email_pattern, null) == null ? null : {
              name     = try(rule.rules.committer_email_pattern.name, null)
              negate   = coalesce(try(rule.rules.committer_email_pattern.negate, null), false)
              operator = coalesce(try(rule.rules.committer_email_pattern.operator, null), "regex")
              pattern  = coalesce(try(rule.rules.committer_email_pattern.pattern, null), "*")
            }

            merge_queue = try(rule.rules.merge_queue, null) == null ? null : {
              check_response_timeout_minutes    = try(rule.rules.merge_queue.check_response_timeout_minutes, null)
              grouping_strategy                 = try(rule.rules.merge_queue.grouping_strategy, null)
              max_entries_to_build              = try(rule.rules.merge_queue.max_entries_to_build, null)
              max_entries_to_merge              = try(rule.rules.merge_queue.max_entries_to_merge, null)
              merge_method                      = try(rule.rules.merge_queue.merge_method, null)
              min_entries_to_merge              = try(rule.rules.merge_queue.min_entries_to_merge, null)
              min_entries_to_merge_wait_minutes = try(rule.rules.merge_queue.min_entries_to_merge_wait_minutes, null)
            }

            pull_request = try(rule.rules.pull_request, null) == null ? null : {
              allowed_merge_methods             = coalesce(try(rule.rules.pull_request.allowed_merge_methods, null), ["merge", "squash"])
              dismiss_stale_reviews_on_push     = coalesce(try(rule.rules.pull_request.dismiss_stale_reviews_on_push, null), true)
              require_code_owner_review         = coalesce(try(rule.rules.pull_request.require_code_owner_review, null), false)
              require_last_push_approval        = coalesce(try(rule.rules.pull_request.require_last_push_approval, null), false)
              required_approving_review_count   = coalesce(try(rule.rules.pull_request.required_approving_review_count, null), 1)
              required_review_thread_resolution = coalesce(try(rule.rules.pull_request.required_review_thread_resolution, null), false)
            }

            copilot_code_review = try(rule.rules.copilot_code_review, null) == null ? null : {
              review_on_push             = coalesce(try(rule.rules.copilot_code_review.review_on_push, null), false)
              review_draft_pull_requests = coalesce(try(rule.rules.copilot_code_review.review_draft_pull_requests, null), false)
            }

            required_deployments = try(rule.rules.required_deployments, null) == null ? null : {
              required_deployment_environments = try(rule.rules.required_deployments.required_deployment_environments, [])
            }

            # Precedence:
            #   1. An explicit required_status_checks rule in the repo YAML wins.
            #   2. Otherwise, if the repo opted in via top-level `required_checks`
            #      AND this ruleset carries the pull_request rule (the PR Gate),
            #      inject those contexts as a required_status_checks rule.
            #   3. Otherwise null (advisory CI, unchanged baseline behavior).
            # do_not_enforce_on_create=true so branch creation is never blocked
            # by a not-yet-reported check.
            required_status_checks = (
              try(rule.rules.required_status_checks, null) != null ? {
                required_check = [
                  for required_check in try(rule.rules.required_status_checks.required_check, []) : {
                    context        = required_check.context
                    integration_id = try(required_check.integration_id, null)
                  }
                ]
                strict_required_status_checks_policy = coalesce(try(rule.rules.required_status_checks.strict_required_status_checks_policy, null), false)
                do_not_enforce_on_create             = coalesce(try(rule.rules.required_status_checks.do_not_enforce_on_create, null), false)
                } : (
                try(rule.rules.pull_request, null) != null && length(repository.required_checks) > 0 ? {
                  required_check = [
                    for context in repository.required_checks : {
                      context        = context
                      integration_id = null
                    }
                  ]
                  strict_required_status_checks_policy = false
                  do_not_enforce_on_create             = true
                } : null
              )
            )

            tag_name_pattern = try(rule.rules.tag_name_pattern, null) == null ? null : {
              name     = try(rule.rules.tag_name_pattern.name, null)
              negate   = coalesce(try(rule.rules.tag_name_pattern.negate, null), false)
              operator = coalesce(try(rule.rules.tag_name_pattern.operator, null), "regex")
              pattern  = coalesce(try(rule.rules.tag_name_pattern.pattern, null), "*")
            }

            required_code_scanning = try(rule.rules.required_code_scanning, null) == null ? null : {
              required_code_scanning_tool = [
                for required_code_scanning_tool in try(rule.rules.required_code_scanning.required_code_scanning_tool, []) : {
                  tool                      = required_code_scanning_tool.tool
                  alerts_threshold          = coalesce(try(required_code_scanning_tool.alerts_threshold, null), "high_or_higher")
                  security_alerts_threshold = coalesce(try(required_code_scanning_tool.security_alerts_threshold, null), "high_or_higher")
                }
              ]
            }

            file_path_restriction = try(rule.rules.file_path_restriction, null) == null ? null : {
              restricted_file_paths = try(rule.rules.file_path_restriction.restricted_file_paths, [])
            }

            max_file_size = try(rule.rules.max_file_size, null) == null ? null : {
              max_file_size = coalesce(try(rule.rules.max_file_size.max_file_size, null), 1)
            }

            # This rule only applies to rulesets with target push.
            max_file_path_length = try(rule.rules.max_file_path_length, null) == null ? null : {
              max_file_path_length = coalesce(try(rule.rules.max_file_path_length.max_file_path_length, null), 255)
            }

            # This rule only applies to rulesets with target push.
            file_extension_restriction = try(rule.rules.file_extension_restriction, null) == null ? null : {
              restricted_file_extensions = try(rule.rules.file_extension_restriction.restricted_file_extensions, [])
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

  #region ------ [ LOCALS | 'repository_environments' ] ------------------------------------- #

  repository_environments = merge(
    {},
    [
      for repository_name, repository in local.all_repositories : {
        for env_name, env in repository.environments :
        "${repository_name}::${env_name}" => merge(env, {
          repository = repository_name
        })
      }
      if !repository.archived && length(repository.environments) > 0
    ]...
  )

  #endregion --- [ LOCALS | 'repository_environments' ] ------------------------------------- #

  #region ------ [ LOCALS | 'repository_environment_branch_policies' ] ---------------------- #

  repository_environment_branch_policies = merge(
    {},
    [
      for env_key, env in local.repository_environments : {
        for index, pattern in env.branch_policies :
        "${env_key}::${format("%02d", index)}::${pattern}" => {
          repository  = env.repository
          environment = env.name
          pattern     = pattern
        }
      }
      if try(env.deployment_branch_policy.custom_branch_policies, false) && length(env.branch_policies) > 0
    ]...
  )

  #endregion --- [ LOCALS | 'repository_environment_branch_policies' ] ---------------------- #

  #region ------ [ LOCALS | 'repository_environment_variables' ] ---------------------------- #

  repository_environment_variables = merge(
    {},
    [
      for env_key, env in local.repository_environments : {
        for var_name, var_value in env.variables :
        "${env_key}::${var_name}" => {
          repository  = env.repository
          environment = env.name
          name        = var_name
          value       = tostring(var_value)
        }
      }
      if length(env.variables) > 0
    ]...
  )

  #endregion --- [ LOCALS | 'repository_environment_variables' ] ---------------------------- #

  #region ------ [ LOCALS | 'repository_environment_secrets' ] ------------------------------ #

  repository_environment_secrets = merge(
    {},
    [
      for env_key, env in local.repository_environments : {
        for secret_name in env.secrets :
        "${env_key}::${secret_name}" => {
          repository  = env.repository
          environment = env.name
          name        = secret_name
        }
      }
      if length(env.secrets) > 0
    ]...
  )

  #endregion --- [ LOCALS | 'repository_environment_secrets' ] ------------------------------ #

}

#% ========================================================================================== %#
#% Input validation layering:                                                                  %#
#%                                                                                             %#
#%   Global invariants (duplicate keys, unknown nested keys, unsupported push rulesets,        %#
#%     auth config, capability gaps) live in local.global_validation_errors and are enforced  %#
#%     by a precondition on terraform_data.framework_validation (41-resources-github.tf).     %#
#%                                                                                             %#
#%   Per-resource invariants (visibility enum, ruleset enforcement, env wait_timer, actions   %#
#%     allowed_actions enum, CODEOWNERS present when require_code_owner_review is true) live  %#
#%     as lifecycle.precondition blocks on the relevant resources, so Terraform's error       %#
#%     messages point at specific resource addresses.                                          %#
#%                                                                                             %#
#%   One intentional advisory-mode exception: check.security_baseline_preview emits a         %#
#%     warning listing capability gaps when security_baseline_mode='compatibility'. It is     %#
#%     a preview for the strict-mode flip, not an enforcement point. See plan Finding 6.      %#
#% ========================================================================================== %#

check "security_baseline_preview" {
  assert {
    condition     = var.security_baseline_mode != "compatibility" || length(local.security_capability_gap_preview) == 0
    error_message = "security_baseline_mode='compatibility' — previewing capability gaps that WILL block plan in strict mode:\n${join("\n", local.security_capability_gap_preview)}"
  }
}
