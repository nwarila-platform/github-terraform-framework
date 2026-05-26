# Terraform Framework Remediation Plan

## Status (as of 2026-05-26)

Most of this plan is now implemented on `main`. The matrix below records the current status of each Decision Summary line and each Finding. Mark a row "Done" only when a code change or explicit policy decision is on `main`; "Open" if work remains; "N/A" if superseded.

| Area / Finding | Status | Notes |
|---|---|---|
| Finding 1 — Default PR gate `require_code_owner_review` coherence | Done | `effective_codeowners` synthesis + `manage_codeowners_files` opt-in flag tracked separately; current `main` keeps CODEOWNERS coherent with the default gate. |
| Finding 2 — Nested YAML deep validation | Done | `terraform_data.framework_validation` enforces deep nested key validation across `pages`, `actions`, `rules`, `environments`, `template`, `security_and_analysis`. |
| Finding 3 — Unsupported push rulesets become plan-blocking errors | Done | `github_supports_push_rulesets` variable + validation; unsupported push rulesets surface as plan-time errors. |
| Finding 4 — `allow_forking` silent no-op | **Done in 2026-05-26 (PRs #62, #63)** | Now an opt-in YAML key with ownership-aware default: personal-account + visibility=private defaults to `null` (provider omits field, bypassing the API rejection); everything else defaults to `false`; YAML can override either. Provider bumped 6.10.2 → 6.12.1 so `null` is honored on PATCH. |
| Finding 5 — Nested optional fields not safe to omit | Done | Resource definitions use `try(..., null)` + `coalesce(...)` pattern throughout `local.all_repositories`; nested optionals normalize to safe defaults. |
| Finding 6 — Private/internal security defaults | Done | `var.github_security_capabilities` + `var.security_baseline_mode` enforce the capability matrix. Capability gaps surface as plan-time errors (Finding 6's "permissive-by-omission" failure mode is now fail-closed). |
| Finding 7 — Branch management assumes seed content | **REJECTED** (per existing `Finding 7: ... [REJECTED]` heading below) | The original framing was rejected; the seed-content concern is handled via documentation rather than additional validation. |
| Finding 8 — Provider auth PAT-only | Done | `var.github_auth_mode` + `var.github_app_auth` declared; PAT remains as explicit fallback. |
| Finding 9 — `repo_default_rules` style coherence | Done | `repo_default_rules` is now a single normalization layer matching the Packer-coherence pattern. |

### Remaining open items

- `manage_codeowners_files = true` opt-in (Finding 1 follow-up). The variable doesn't currently exist on `main`; the unmerged `chore/standardize-fleet-bead9a4` branch had it. Future work: declare the variable on `main` + add the corresponding `github_repository_file.codeowners` toggle + the two test cases that exercise both states.
- `terraform-provider-github` upstream behavior. The Finding 4 fix depends on the provider honoring `null` to omit the field from PATCH. Provider 6.12 does. Any provider downgrade would re-open the finding; pin discipline (Renovate-tracked) keeps that risk low.

### Maintenance protocol

When a Finding's status changes, update this table in the same PR that lands the change. Drift between the documented status and reality undermines the table's value; the goal is that this table is the single source of truth for what the framework's "remediation" surface looks like.

## Purpose

This document consolidates the adversarial review findings for the Terraform framework in this repository into a single decision package.

It is intended to answer four questions in one place:

1. What is wrong today.
2. Why each issue matters from an enterprise-quality perspective.
3. What the recommended fix is for each issue.
4. In what order the fixes should be implemented and validated.

Current scope note:

- This review is focused on the framework code under `terraform/`.
- In the current checked-out workspace, `terraform/repos/public` and `terraform/repos/private` contain only `.gitkeep`, so this plan does not assume any active repo YAML inputs are present on disk.

## Executive Summary

The framework is directionally strong, but it is not yet at a highest-enterprise-quality bar because several policy paths fail open instead of fail closed.

The main problems are:

- default repository policy is internally inconsistent in the `CODEOWNERS` path
- nested YAML keys are not deeply validated
- unsupported features can be silently dropped instead of blocking apply
- at least one accepted input (`allow_forking`) is a silent no-op
- several nested optional fields are not actually safe to omit
- private and internal repo security defaults are permissive-by-omission
- branch orchestration assumes a seed branch exists
- provider authentication is hard-wired to a long-lived PAT

Recommended direction:

- keep the current framework shape
- harden it around a fail-closed validation layer
- introduce explicit capability modeling for GitHub security features
- add a first-class GitHub App authentication path
- reject unsupported inputs until they have a real provider-backed implementation

## Decision Summary

| Area | Current Problem | Recommended Fix | Decision |
|---|---|---|---|
| Default PR gate | `require_code_owner_review = true` can fail framework usage by default | Keep the gate, but make `CODEOWNERS` resolution explicit and coherent | Adopt |
| Nested YAML validation | Only top-level keys are validated; nested typos fall back to permissive defaults | Add deep validation for every nested object and enum | Adopt |
| Push rulesets | Unsupported push rulesets are silently skipped | Convert unsupported push rulesets into plan-blocking validation errors | Adopt |
| `allow_forking` | Accepted input is ignored | Reject the input until a provider-backed implementation exists | Adopt now |
| Nested optional fields | Missing nested fields can crash evaluation | Replace direct attribute dereferences with safe normalization | Adopt |
| Security baseline | Private/internal repos default to null security settings | Add explicit capability model and strict baseline mode | Adopt |
| Branch bootstrapping | Branch management assumes repository seed content exists | Validate seed-content prerequisites before branch/rules/file resources | Adopt |
| Provider auth | PAT-only provider auth | Add GitHub App auth mode and keep PAT only as explicit fallback | Adopt |

## Guiding Principles

These should govern all remediation work:

- Fail closed, never fail open.
- No silent no-ops.
- Defaults must be internally coherent.
- Unsupported platform constraints must be explicit.
- Security capability gaps must be modeled, not hidden.
- YAML author mistakes must surface as plan-blocking errors with precise messages.

## Finding 1: Default PR Gate Is Internally Inconsistent

### Current Context

The default ruleset requires code owner review:

```hcl
# terraform/11-variables.gitlab.tf:235-253
{
  name          = "Pull Request Gate"
  target        = "branch"
  enforcement   = "active"
  bypass_actors = []
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
```

The ruleset resource then blocks apply unless `codeowners` exists:

```hcl
# terraform/41-resources-gitlab.tf:408-413
precondition {
  condition = (
    try(each.value.rules.pull_request.require_code_owner_review, false) == false
    || local.all_repositories[each.value.repository].codeowners != null
  )
  error_message = "Ruleset '${each.key}' enables require_code_owner_review but repository '${each.value.repository}' does not define a 'codeowners' field. The framework will not enable a CODEOWNERS gate without provisioning the CODEOWNERS file."
}
```

The design document also states that a `CODEOWNERS` file is part of the intended model:

```text
# DESIGN.md:778-780
Requires at least one approving review from a designated code owner (defined in `.github/CODEOWNERS`).
Recommendation: `true`. Even for a solo developer, a CODEOWNERS file (mapping `* @NWarila`) formalizes ownership and creates an audit trail.
```

### Why This Matters

- A repo that relies on framework defaults can fail unexpectedly.
- The framework default is not self-sufficient.
- This is a policy contradiction, not just a missing convenience.

### Recommended Fix

Keep `require_code_owner_review = true`, but make `CODEOWNERS` resolution explicit and deterministic.

### Proposed Implementation

1. Introduce an effective `CODEOWNERS` value in normalization.
2. Add a default path for personal-account mode.
3. Require explicit `codeowners` for organization mode.

Recommended model:

```hcl
variable "repo_default_codeowners" {
  description = "Default CODEOWNERS content for personal-account repositories when code owner review is enabled."
  type        = string
  default     = null
}
```

Normalized behavior:

```hcl
effective_codeowners = (
  try(repository.codeowners, null) != null
  ? repository.codeowners
  : (
      !var.github_is_organization
      ? coalesce(var.repo_default_codeowners, "* @${var.github_owner}\n")
      : null
    )
)
```

Validation behavior:

- If `github_is_organization = true` and code-owner review is enabled, require explicit `codeowners`.
- If `github_is_organization = false`, synthesize `* @${var.github_owner}` unless overridden.

### Acceptance Criteria

- A default personal-account repo can apply without explicitly setting `codeowners`.
- An organization repo with code-owner review and no `codeowners` fails with a clear message.
- `github_repository_file.codeowners` uses the effective value, not only raw YAML.

## Finding 2: Nested YAML Validation Fails Open

### Current Context

Only top-level repo keys are validated:

```hcl
# terraform/30-locals.tf:34-57
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
  "vulnerability_alerts", "ignore_vulnerability_alerts_during_read", "dependabot_security_updates",
  "pages", "security_and_analysis", "template",
  "branches", "rules", "actions", "environments",
  "codeowners",
])

repos_with_unknown_keys = {
  for name, repo in local.repos_from_yaml :
  name => setsubtract(keys(repo), local.allowed_repo_keys)
  if length(setsubtract(keys(repo), local.allowed_repo_keys)) > 0
}
```

Nested objects then default in security-sensitive ways:

```hcl
# terraform/30-locals.tf:379-452
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
    verified_allowed = coalesce(
      try(repository.actions.allowed_actions_config.verified_allowed, null),
      true
    )
    patterns_allowed = try(
      repository.actions.allowed_actions_config.patterns_allowed,
      []
    )
  }
}

environments = {
  for env_name, env in try(repository.environments, {}) : env_name => {
    wait_timer = coalesce(try(env.wait_timer, null), 0)
    can_admins_bypass = coalesce(try(env.can_admins_bypass, null), true)
    prevent_self_review = coalesce(try(env.prevent_self_review, null), false)
    ...
  }
}
```

### Why This Matters

- A typo in nested YAML can silently weaken governance.
- A misspelled secure setting can downgrade to a permissive default.
- This is exactly the class of defect enterprise policy-as-code is supposed to prevent.

### Recommended Fix

Add deep schema validation for all nested objects and enumerated values before any normalization defaults are applied.

### Proposed Implementation

Add local validators for:

- `actions`
- `actions.allowed_actions_config`
- `environments`
- `environments.reviewers`
- `environments.deployment_branch_policy`
- `rules`
- `rules.conditions`
- `rules.bypass_actors`
- `rules.rules`
- all nested ruleset sub-objects

Recommended validation pattern:

```hcl
locals {
  validation_errors = concat(
    local.unknown_top_level_key_errors,
    local.unknown_nested_key_errors,
    local.invalid_enum_errors,
    local.unsupported_feature_errors,
    local.bootstrap_errors
  )
}
```

Use one dedicated plan-blocking validation point:

```hcl
resource "terraform_data" "framework_validation" {
  input = local.validation_errors

  lifecycle {
    precondition {
      condition     = length(local.validation_errors) == 0
      error_message = join("\n", local.validation_errors)
    }
  }
}
```

If you prefer not to add `terraform_data`, the same aggregated checks can be placed on an existing always-present resource, but a dedicated validation node is cleaner.

### Acceptance Criteria

- Unknown nested keys always fail plan.
- Invalid enum values always fail plan.
- Defaults apply only when known keys are omitted, not when keys are misspelled.

## Finding 3: Unsupported Push Rulesets Are Silently Dropped

### Current Context

Push rulesets are filtered out instead of rejected:

```hcl
# terraform/30-locals.tf:756-763
if length(repository.rules) > 0 && (
  coalesce(try(rule.target, null), "branch") != "push"
  || (
    var.github_supports_push_rulesets
    && contains(["private", "internal"], repository.visibility)
  )
)
```

### Why This Matters

- A repo author can declare a push ruleset and get no enforcement.
- A successful apply can misrepresent actual security posture.
- Silent dropping is unacceptable for enterprise governance.

### Recommended Fix

Keep the filter for graph safety if needed, but add a separate validation error that blocks plan whenever a requested push ruleset is unsupported.

### Proposed Implementation

Add:

```hcl
locals {
  unsupported_push_ruleset_errors = flatten([
    for repository_name, repository in local.all_repositories : [
      for index, rule in repository.rules : (
        coalesce(try(rule.target, null), "branch") == "push" &&
        !(
          var.github_supports_push_rulesets &&
          contains(["private", "internal"], repository.visibility)
        )
      )
      ? "Repository '${repository_name}' rule ${index} requests target='push', but push rulesets are not supported for this owner/plan/visibility combination."
      : null
    ]
  ])
}
```

Then filter out `null` entries and add this to the global validation errors.

### Acceptance Criteria

- A requested unsupported push ruleset fails plan.
- No push ruleset request can disappear silently.

## Finding 4: `allow_forking` Is a Silent No-Op

### Current Context

The framework accepts the key:

```hcl
# terraform/30-locals.tf:41-42
"allow_auto_merge", "allow_forking", "allow_merge_commit", "allow_rebase_merge",
```

It normalizes the value:

```hcl
# terraform/30-locals.tf:212
allow_forking = try(repository.allow_forking, null)
```

But the resource layer does not apply it:

```hcl
# terraform/41-resources-gitlab.tf:35-36
# allow_forking is org-only; set via github_repository_setting or per-repo override
# allow_forking = each.value.allow_forking
```

### Why This Matters

- Users can believe they are managing a governance control that is not actually enforced.
- This is a silent no-op and therefore a policy integrity defect.

### Recommended Fix

Reject the input immediately until there is a verified provider-backed implementation in this framework.

### Proposed Implementation

Phase 1 fix:

- remove `allow_forking` from accepted top-level repo keys, or
- keep it accepted but add a plan-blocking validation error if it is ever set

Recommended strict version:

```hcl
precondition {
  condition     = each.value.allow_forking == null
  error_message = "Repository '${each.key}' sets allow_forking, but this framework does not currently manage that setting. Remove it until provider-backed support is implemented."
}
```

Deferred future enhancement:

- reintroduce support only after the framework owns a real resource path and tests it

### Acceptance Criteria

- `allow_forking` can never be silently ignored.
- Any use of `allow_forking` is either enforced or rejected.

## Finding 5: Several Nested Optional Fields Are Not Actually Safe

### Current Context

Example from `pages`:

```hcl
# terraform/30-locals.tf:312-318
pages = try(repository.pages, null) == null ? null : {
  source = try(repository.pages.source, null) == null ? null : {
    branch = repository.pages.source.branch
    path   = try(repository.pages.source.path, null)
  }
  build_type = try(repository.pages.build_type, null)
  cname      = try(repository.pages.cname)
}
```

Example from ruleset normalization:

```hcl
# terraform/30-locals.tf:549-565
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
```

### Why This Matters

- A partially specified YAML object can crash evaluation.
- Operators will experience plan failures that look random or inconsistent.
- Safe optional fields are required for a reliable configuration interface.

### Recommended Fix

Replace all direct nested dereferences with safe `try(..., null)` access, and normalize every nested object from validated inputs only.

### Proposed Implementation

Pattern to apply everywhere:

```hcl
branch_name_pattern = try(rule.rules.branch_name_pattern, null) == null ? null : {
  name     = try(rule.rules.branch_name_pattern.name, null)
  negate   = coalesce(try(rule.rules.branch_name_pattern.negate, null), false)
  operator = coalesce(try(rule.rules.branch_name_pattern.operator, null), "regex")
  pattern  = coalesce(try(rule.rules.branch_name_pattern.pattern, null), "*")
}
```

Also fix similar direct accesses in:

- `pages`
- `template`
- `pull_request`
- `merge_queue`
- `required_deployments`
- `required_status_checks`
- `required_code_scanning`
- `file_path_restriction`
- `file_extension_restriction`
- `max_file_size`
- `max_file_path_length`

### Acceptance Criteria

- Omitting any optional nested field does not crash evaluation.
- Invalid shapes fail validation cleanly instead of throwing expression errors.

## Finding 6: Private/Internal Security Defaults Are Too Weak

### Current Context

Private and internal defaults are intentionally null:

```hcl
# terraform/30-locals.tf:84-112
repo_security_defaults = {
  public = {
    advanced_security                     = null
    code_security                         = null
    secret_scanning                       = true
    secret_scanning_push_protection       = true
    secret_scanning_ai_detection          = null
    secret_scanning_non_provider_patterns = null
  }
  private = {
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
```

### Why This Matters

- The framework silently omits security controls on the most sensitive repos.
- Platform entitlement uncertainty is being modeled as silent permissiveness.
- Enterprise-grade policy needs explicit capability decisions.

### Recommended Fix

Introduce an explicit GitHub security capability model and a strict baseline mode.

### Proposed Implementation

Add owner capability inputs:

```hcl
variable "github_security_capabilities" {
  type = object({
    advanced_security                     = bool
    code_security                         = bool
    secret_scanning                       = bool
    secret_scanning_push_protection       = bool
    secret_scanning_ai_detection          = bool
    secret_scanning_non_provider_patterns = bool
  })
}

variable "security_baseline_mode" {
  type        = string
  default     = "strict"
  description = "strict blocks unsupported baseline requirements; compatibility allows explicit opt-down."
}
```

Recommended behavior:

- In `strict` mode:
  - required baseline settings must be explicitly modeled
  - unsupported required settings fail plan
- In `compatibility` mode:
  - null behavior is allowed only when explicitly chosen by the operator

Recommended baseline:

- public: keep secret scanning and push protection enabled
- private/internal: require explicit capability declaration and enable every supported control that is intended as baseline

### Acceptance Criteria

- Private/internal repos do not silently omit security controls.
- Capability gaps are explicit in configuration and error messages.
- Strict mode becomes the default enterprise posture.

## Finding 7: Branch Management Assumes Seed Content Exists [REJECTED]

**Status: Rejected during adversarial review (Round 2).**

Rationale: the failure mode this finding addresses — an operator explicitly setting `auto_init: false` with no `fork` or `template` configured, causing `github_branch_default` to fail — is rare (the framework default is `auto_init: true`, so the operator must intentionally override) and the provider error ("cannot rename branch: no default branch exists") is clear enough to diagnose.

Adding a `manage_branches` toggle or a seed-content precondition would introduce new YAML keys, new locals, and new resource filters to protect against a rare footgun with an adequate native error. Under the framework's simplicity and Packer-coherence principles, this is overengineering.

**Remediation:** document the constraint in the repo YAML schema documentation. A one-line note is sufficient:

> If `auto_init: false` is set, you must also configure either `template` or `fork`, otherwise branch management will fail at apply time.

**Meta-principle locked in for this review pass:** where the provider already fails clearly, the framework does not add validation for the sake of it. Validation earns its keep when the provider's error is cryptic or misleading; not when it is merely later than we'd like.

---

### Original Finding (preserved for history)

## Finding 7-original: Branch Management Assumes Seed Content Exists

### Current Context

Repository creation defaults `auto_init` from settings:

```hcl
# terraform/30-locals.tf:259-262
auto_init = coalesce(
  try(repository.auto_init, null),
  local.repo_setting_defaults.auto_init
)
```

Branch defaults assume the target branch can be renamed or managed:

```hcl
# terraform/30-locals.tf:496-500
branch_defaults = {
  for repository in local.all_repositories : repository.name => {
    repository = repository.name
    branch     = repository.branches[0]
    rename     = true
  }
  if !repository.archived && length(repository.branches) > 0
}
```

### Why This Matters

- Empty repositories without seed content do not have a branch to rename or branch from.
- This can break `github_branch_default`, `github_branch`, and `github_repository_file.codeowners`.

### Recommended Fix

Make branch and file management contingent on repository seed content.

### Proposed Implementation

Add normalized seed-content state:

```hcl
has_seed_content = (
  each.value.auto_init
  || each.value.fork
  || each.value.template != null
)
```

Then validate:

- if a repo manages branches, default branch, or repo files, it must have seed content
- otherwise fail with a clear message

Recommended validation message:

```text
Repository 'X' manages branches or repository files but has no seed content path. Set auto_init=true, configure template, or configure fork source.
```

### Acceptance Criteria

- No empty repo attempts branch/default-branch/file management without seed content.
- Empty repo use cases fail early with clear remediation instructions.

## Finding 8: Provider Authentication Is PAT-Only

### Current Context

The current provider block only supports a PAT variable:

```hcl
# terraform/01-providers-gitlab.tf:6-8
provider "github" {
  token = var.github_token
  owner = var.github_owner
}
```

The upstream provider source handles `app_auth` in addition to `token`:

```text
# integrations/terraform-provider-github github/provider.go
providerConfigure reads `token` and also checks `d.Get("app_auth")`.
The provider source shows `app_auth` handling alongside token-based configuration.
```

Source used:

- https://github.com/integrations/terraform-provider-github/blob/main/github/provider.go

### Why This Matters

- Long-lived PATs are a weak default for enterprise automation.
- GitHub App auth gives better permission scoping, auditability, and rotation hygiene.

### Recommended Fix

Add explicit authentication modes:

- `app` as the preferred mode
- `token` as a deliberate fallback

### Proposed Implementation

Suggested variables:

```hcl
variable "github_auth_mode" {
  type    = string
  default = "app"
}

variable "github_token" {
  type      = string
  sensitive = true
  default   = null
}

variable "github_app_auth" {
  type = object({
    id              = string
    installation_id = string
    pem_file        = string
  })
  sensitive = true
  default   = null
}
```

Suggested provider pattern:

```hcl
provider "github" {
  owner = var.github_owner
  token = var.github_auth_mode == "token" ? var.github_token : null

  dynamic "app_auth" {
    for_each = var.github_auth_mode == "app" ? [var.github_app_auth] : []
    content {
      id              = app_auth.value.id
      installation_id = app_auth.value.installation_id
      pem_file        = app_auth.value.pem_file
    }
  }
}
```

Validation rules:

- `github_auth_mode` must be `app` or `token`
- exactly one auth source must be configured
- PAT mode should be documented as break-glass, not default

### Acceptance Criteria

- The framework supports GitHub App auth cleanly.
- PAT mode remains available only as an explicit operator choice.
- CI can run without requiring a long-lived personal token.

## Finding 9: `repo_default_rules` Violates Packer-Coherence Style

### Current Context

The framework's sibling Packer framework (`proxmox-packer-framework`) establishes a house style for typed variables: **fully-typed, fully-required objects with zero `optional()` usage**. Every consumer input must be explicitly provided, and the type system enforces it. `variables.pkr.hcl` in the Packer framework contains zero `optional()` calls.

The existing [terraform/11-variables.gitlab.tf](terraform/11-variables.gitlab.tf) `repo_default_rules` variable, however, is heavily built on `optional()`:

```hcl
# terraform/11-variables.gitlab.tf:44-213
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
    ...
```

Nearly every field is `optional()`. This is the Terraform-comfort-zone idiom, not the house style.

### Why This Matters

- Cross-framework coherence: a developer reading the Packer framework and then the Terraform framework should recognize the same style. `optional()` breaks that recognition.
- Defaults hide: `optional()` lets the type system silently fill gaps, which is the same class of "fail open" risk Finding 2 is fixing at the YAML layer. Applying it consistently at the variable layer means no silent gap-filling anywhere.
- Explicitness: a fully-required type forces the consumer (or the default block) to declare every field, making the contract auditable by reading the variable declaration alone.

### Recommended Fix

Refactor `repo_default_rules` (and any future typed variables) to:

1. Remove every `optional()` wrapper from the type declaration.
2. Fully spell out the default value with every field present.
3. Use explicit `null` in the default where "unset" is a valid state — never an omitted key.

### Scope

**Deferred — not part of the current remediation pass.** This is a ~170-line style refactor across one variable, with no behavioral change. It is tracked here so it is not forgotten, and should be scheduled as a standalone PR after the current remediation lands.

### Forward-Looking Rule

All **new** typed variables introduced by the current remediation pass (capability matrix in Finding 6, GitHub App auth in Finding 8, any others) **must** be written in Packer-coherence style from the start: fully required, no `optional()`, explicit defaults spelled out in full.

### Acceptance Criteria

- Finding 9 is tracked in this document and referenced in the backlog.
- All new variables added by Phases 1–4 contain zero `optional()` calls.
- A future dedicated PR refactors `repo_default_rules` to match.

## Recommended Implementation Sequence

### Phase 0: Execution Prerequisites

Do these first:

1. Install a compatible Terraform CLI version.
   Current repo requirement:

   ```hcl
   # terraform/00-providers.tf:5-8
   terraform {
     required_version = "1.14.3"
   }
   ```

   Current local observation from this review:

   - installed CLI was `Terraform v1.13.2`
   - that blocks `terraform init` and `terraform validate`

2. Run `terraform init -backend=false` after upgrading Terraform.
3. Confirm provider plugins are available locally before validation work begins.

### Phase 1: Fail-Closed Guardrails

Implement these together:

1. aggregated validation errors
2. deep nested key validation
3. enum validation
4. unsupported push ruleset validation
5. `allow_forking` rejection
6. seed-content validation

Reason:

- This phase stops the framework from silently accepting unsafe or unsupported input.

### Phase 2: Normalization Hardening

Implement these next:

1. safe nested optional access refactor
2. effective `CODEOWNERS` normalization
3. repo file/resource consumption of normalized values

Reason:

- Once validation is strict, normalization becomes simpler and safer.

### Phase 3: Security Baseline Modeling

Implement:

1. `github_security_capabilities`
2. `security_baseline_mode`
3. strict-mode validation and defaults

Reason:

- This is the biggest governance behavior change and should be introduced after the validation foundation is stable.

### Phase 4: Authentication Upgrade

Implement:

1. `github_auth_mode`
2. `github_app_auth`
3. PAT fallback
4. provider auth validation

Reason:

- This is operationally important, but it is somewhat orthogonal to input hardening.

## Validation and Test Plan

Minimum verification bar for the remediation work:

1. `terraform fmt -check`
2. `terraform validate`
3. negative test fixtures that intentionally fail validation
4. at least one positive personal-account fixture
5. at least one positive organization-mode fixture

Recommended negative fixture cases:

- repo with misspelled nested `actions` key
- repo with unsupported push ruleset
- repo with `allow_forking` set
- org-mode repo with code-owner review and no `codeowners`
- repo with branch management but `auto_init = false` and no template/fork
- repo with security baseline requirements unsupported by declared capabilities

Recommended positive fixture cases:

- personal-account repo relying on synthesized `CODEOWNERS`
- org-mode repo with explicit `CODEOWNERS`
- private repo with declared security capabilities and strict baseline
- app-auth provider configuration

## Recommended Decisions

These are the decisions I recommend making before implementation starts:

1. Approve fail-closed behavior as the default standard.
2. Approve synthesized `CODEOWNERS` only for personal-account mode.
3. Approve removing or rejecting `allow_forking` until it is truly implemented.
4. Approve strict security capability modeling instead of silent null defaults.
5. Approve GitHub App auth as the preferred provider mode.

## Proposed Work Output

If this plan is approved, the implementation pass should produce:

- hardened validation locals
- one dedicated framework validation resource or equivalent precondition strategy
- normalized effective `CODEOWNERS` behavior
- safe nested object normalization throughout `terraform/30-locals.tf`
- stricter security capability inputs and defaults
- GitHub App provider auth support
- updated documentation in `README.md` and `DESIGN.md`

## Final Recommendation

The best approach is not a broad rewrite. The framework already has a solid shape.

The right move is a focused hardening pass with this order:

1. stop silent misconfiguration
2. make defaults internally coherent
3. make unsupported platform gaps explicit
4. upgrade authentication posture

That path gives the biggest security and correctness gain with the least architectural churn.

---

## Adversarial Review (Round 2)

Reviewed by: Claude. Disposition: **Do not implement as-is.** The plan is directionally correct and Findings 1–5 can ship close to as written, but Findings 6–8 and Phase 0 have blocking issues that must be resolved first. Specific concerns and requested amendments below. Please respond inline or revise and re-submit.

### Blocking concerns

#### B1. Module-vs-root question is unresolved, and Finding 8 depends on the answer

Context from prior review: this repo declares both a `backend "s3"` block and `provider "github"` / `provider "aws"` blocks, which are root-module traits, but is described as a framework consumed by `github-terraform-runner`, which implies a reusable module. This was flagged previously and never resolved.

Finding 8 (GitHub App auth) adds more logic to the `provider "github"` block. If this repo is ultimately a reusable module, that provider block should not exist here at all — the runner owns provider configuration. Implementing Finding 8 in this repo would be wasted work and would actively make it harder to convert to a pure module later.

**Required resolution before Phase 4:** declare in this document whether the framework is (a) a root module that the runner invokes via `terraform apply` with backend/var files, or (b) a reusable child module that the runner wraps with its own `providers.tf`. Then either:

- (a) keep Finding 8 here and also fix the backend config (unconfigured `backend "s3"` was a prior critical finding), or
- (b) move Finding 8 to the runner repo and strip `backend` + `provider` blocks from this framework.

#### B2. Security capability model (Finding 6) is too flat

`github_security_capabilities` is proposed as a single object of six booleans. In reality GitHub security features depend on **both** the owner's plan **and** the repo visibility — for example, GHAS / `advanced_security` is free on public repos and licensed on private repos; secret scanning push protection coverage differs by plan; AI detection is GHAS-gated. A single flat bool loses that matrix.

**Requested amendment:** model capabilities as `map(visibility => object(features))`, or explicitly document that each flag means "this owner/plan supports this feature for any visibility the framework will enable it on." I prefer the explicit matrix.

#### B3. Finding 6 has no migration strategy

Flipping the default security baseline to `strict` on an existing state will cause mass drift or plan failures on repos where `security_and_analysis` is currently null. The plan does not address rollout.

**Requested amendment:** ship `security_baseline_mode` with **`compatibility` as the initial default**, with a documented "flip to strict in release N+1" milestone. Add a precondition that surfaces the list of repos that would fail under strict, so operators can see the gap before flipping.

#### B4. Phase 0 treats the `required_version` pin as an environment problem, not a framework bug

The plan's Phase 0 says "install Terraform 1.14.3 to match `required_version`." That dodges the root cause: `required_version = "1.14.3"` is an **exact pin**, which was flagged as a defect in the original review (item #9). Exact pins break CI on every patch release and are not an enterprise practice.

**Requested amendment:** as part of Phase 0, change `required_version` to `">= 1.14.3, < 2.0.0"` (or `"~> 1.14"`). Then the CLI mismatch fixes itself for any 1.14+ user.

### Significant concerns (non-blocking but should be addressed before merge)

#### S1. Finding 1: ruleset must depend on CODEOWNERS file, not just on the branch

If `require_code_owner_review = true`, the ruleset activation must happen **after** `github_repository_file.codeowners` writes the file to the default branch — otherwise the first PR post-apply is blocked by a rule pointing at a nonexistent CODEOWNERS file. The plan provisions the file but does not add a `depends_on` from the ruleset to the file resource.

**Requested amendment:** add an explicit `depends_on = [github_repository_file.codeowners]` on `github_repository_ruleset.branch`, or make the dependency implicit via an attribute reference in a precondition.

#### S2. Finding 2: aggregated `validation_errors` loses locality

Bundling all errors into one `terraform_data` node produces a single wall-of-text error message that hides which resource / which YAML file / which line caused the failure. That's a regression vs. the per-resource preconditions added in the prior remediation.

**Requested amendment:** use `terraform_data` **only** for genuinely global invariants (duplicate keys across files, unknown top-level keys, unsupported-feature gating). Keep per-instance preconditions on the relevant resources for repo-scoped checks so error messages stay localized and actionable.

Also: `terraform_data.input = local.validation_errors` will trigger a replacement any time the error list changes. That's harmless but noisy in plans. Prefer `lifecycle.precondition` on a `terraform_data` with a static input, so the node is stable across plans.

#### S3. Finding 3: null-filter step is implied but not shown

`flatten([for ... : ... ? "error" : null])` leaves nulls in the list; pushing that into `join("\n", ...)` will render `"null"` strings. Show the filter: `[for e in flatten(...) : e if e != null]`.

#### S4. Finding 5: enumerate the actual bugs, don't just describe the pattern

The current code has at least one concrete defect the plan should call out by name so it isn't missed:

- [terraform/30-locals.tf](terraform/30-locals.tf) `cname = try(repository.pages.cname)` — single-arg `try` is a no-op; should be `try(..., null)`.
- In every `branch_name_pattern` / `commit_*_pattern` / `tag_name_pattern` block, `coalesce(rule.rules.X.negate, false)` directly dereferences `negate` without a `try()` wrapper. If `negate` is omitted from YAML, plan crashes with "This object does not have an attribute named negate." Same for `operator` and `pattern` when the pattern block is present but partially populated.
- `merge_queue` block uses direct attribute access (`rule.rules.merge_queue.check_response_timeout_minutes`) with no `try()`. If any merge_queue sub-field is omitted, plan crashes.
- `required_status_checks.strict_required_status_checks_policy` and `do_not_enforce_on_create` are wrapped in `coalesce()` without `try()`.

**Requested amendment:** list these sites (and any peers found during implementation) in the plan so the fix is verifiable, not aspirational.

#### S5. Finding 7: clarify first-apply vs steady-state semantics

`has_seed_content = auto_init || fork || template != null` is correct at **repo creation** time but misleading afterward. An existing repo that was bootstrapped with `auto_init = true` a year ago, then had `auto_init` flipped to `false` in YAML (harmless — it's ignored post-creation), would now fail the seed-content precondition for no real reason.

**Requested amendment:** either

- (a) Scope the seed-content check to "repos not yet in state" via a data-source existence lookup, or
- (b) Reframe the check as "at least one of these was once true" and document that flipping them later is a no-op, or
- (c) Introduce an explicit `manage_branches` per-repo toggle (default true) that operators disable for repos where they know the framework shouldn't touch branches.

I recommend (c) — it's the most explicit and avoids data-source round-trips.

### Minor concerns

- **Finding 4:** agreed, ship as written. Suggest also removing `allow_forking` from `allowed_repo_keys` so it's rejected at the unknown-key stage with a clear message, rather than at a dedicated precondition — one less code path.
- **Finding 8:** `installation_id` should be `number`, not `string` (the provider accepts both but consistency helps). `pem_file` accepts either a file path or PEM contents; document which the framework expects and validate in a precondition.
- **Validation and Test Plan:** listing `terraform fmt -check` / `terraform validate` is insufficient for "highest-enterprise-quality." Add `tflint`, `tfsec` or `trivy config`, and `checkov` to the required bar, even if execution lives in the runner's CI. If the framework does not own CI, state so explicitly and name the runner target where these gates run.
- **Docs:** the plan proposes README / DESIGN.md updates but does not call out updating the YAML schema documentation, which is the consumer contract. Add that as an explicit deliverable.

### Decisions requested from Codex

Please respond with:

1. **Module-or-root?** (blocks B1 and Finding 8)
2. **Capability matrix shape?** (blocks B2 — flat object, or visibility-keyed map)
3. **Baseline rollout?** (blocks B3 — confirm compatibility-first default)
4. **Phase 0 pin fix?** (blocks B4 — confirm loosening `required_version`)
5. Confirm acceptance of S1–S5 amendments, or push back with reasoning.

Once B1–B4 are resolved and S1–S5 are folded into the plan, I'm prepared to implement Phases 1 and 2 in one pass. Phases 3 and 4 should be separate PRs because they introduce variables the runner will need to set.
