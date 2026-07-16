# Test Coverage Matrix

Terraform has no native line-coverage tooling (no LCOV, no Codecov integration). This document tracks **logical path coverage** manually. Every code path that matters — validation branches, normalization paths, per-resource preconditions, edge cases — gets a row and a checkmark.

## Scope and philosophy

This matrix covers the boundaries where a regression can hide. It explicitly does NOT test:

- Pass-through resource attributes (`attr = each.value.field`) — if the local is right, the attribute is right.
- `dynamic` block emission from validated locals — same reason.
- Provider internals (token validity, API calls) — not our code.
- Apply-time ordering (`depends_on` under concurrency) — requires real apply; belongs in runner integration tests.

The `REVIEW_REMEDIATION_PLAN.md` adversarial review set the principle: **test the boundary, not the implementation**. This matrix enforces that.

## Maintenance rules

1. When you add a new code path (validation check, normalization branch, resource precondition), add a row with ❌.
2. When you add a test that exercises an existing path, flip the row to ✅ and record the `run` block name and file.
3. PR review checklist: *"Does this PR add any ❌ rows? Does it flip any ✅ back to ❌?"*
4. `terraform test` must be green before merging; any failing run is a blocker.

## Run the suite

```bash
cd terraform
terraform init -backend=false
terraform test
```

---

## Global validation (`terraform_data.framework_validation`)

| # | Path | Status | Test |
|---|---|---|---|
| G01 | Duplicate repo keys across `public/` and `private/` | ✅ | `validation.tftest.hcl::rejects_duplicate_repo_keys` |
| G02 | Unknown top-level YAML key | ✅ | `validation.tftest.hcl::rejects_unknown_top_level_key` |
| G03 | `allow_forking` defaults public→true, internal→false, organization-private→false, personal-private→null; YAML overrides; public explicit false is rejected | ✅ | `forking.tftest.hcl` F1–F7 |
| G04 | Unknown nested: `actions.*` (top) | ✅ | `validation.tftest.hcl::rejects_unknown_nested_key` + multi-typo |
| G05 | Unknown nested: `actions.allowed_actions_config.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G06 | Unknown nested: `pages.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G07 | Unknown nested: `pages.source.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G08 | Unknown nested: `template.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G09 | Unknown nested: `security_and_analysis.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G10 | Unknown nested: `environments[].*` (top) | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G11 | Unknown nested: `environments[].reviewers.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G12 | Unknown nested: `environments[].deployment_branch_policy.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G13 | Unknown nested: `rules[].*` (top) | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G14 | Unknown nested: `rules[].conditions.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G15 | Unknown nested: `rules[].bypass_actors[].*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G16 | Unknown nested: `rules[].rules.*` (top) | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G17 | Unknown nested: `rules[].rules.pull_request.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G18 | Unknown nested: `rules[].rules.merge_queue.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G19 | Unknown nested: `rules[].rules.copilot_code_review.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G20 | Unknown nested: `rules[].rules.required_status_checks.*` | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G21 | Unknown nested: all 5 `*_pattern` blocks (uniform walker) | ✅ | `validation.tftest.hcl::rejects_multiple_nested_typos_in_one_repo` |
| G22 | Push ruleset: public + unsupported | ✅ | `validation.tftest.hcl::rejects_unsupported_push_ruleset` |
| G23 | Push ruleset: public + supports=true (still fails) | ✅ | `validation.tftest.hcl::push_ruleset_public_supports_true_still_fails` |
| G24 | Push ruleset: private + unsupported | ✅ | `validation.tftest.hcl::push_ruleset_private_supports_false_fails` |
| G25 | Push ruleset: private + supported (positive) | ✅ | `normalization.tftest.hcl::push_ruleset_on_private_when_supported_plans_clean` |
| G26 | Push ruleset: internal + supported (positive) | ✅ | `validation.tftest.hcl::push_ruleset_internal_supports_true_passes` |
| G27 | Push ruleset: internal + unsupported | ✅ | `validation.tftest.hcl::push_ruleset_internal_supports_false_fails` |
| G28 | Branch-target ruleset on any visibility → passes | ✅ | `validation.tftest.hcl::good_minimal_plans_clean` |
| G29 | Auth: token mode, `github_token == null` | ✅ | `validation.tftest.hcl::rejects_token_mode_missing_token` |
| G30 | Auth: app mode, `github_app_auth == null` | ✅ | `validation.tftest.hcl::rejects_app_mode_missing_app_auth` |
| G31 | Auth: token mode with both sources set | ✅ | `validation.tftest.hcl::rejects_token_mode_with_app_auth_also_set` |
| G32 | Auth: app mode with both sources set | ✅ | `validation.tftest.hcl::rejects_app_mode_with_token_also_set` |
| G33 | Auth: valid token mode → passes | ✅ | `validation.tftest.hcl::good_minimal_plans_clean` (default) |
| G34 | Auth: valid app mode → passes | ✅ | `validation.tftest.hcl::valid_app_auth_plans_clean` |
| G35 | Strict baseline + capability gap | ✅ | `validation.tftest.hcl::strict_mode_fails_on_capability_gap` |
| G36 | Strict baseline + no gap | ✅ | `security.tftest.hcl::strict_mode_no_gap_plans_clean` |
| G37 | Compat baseline + gap + populated preview | ✅ | `validation.tftest.hcl::compatibility_mode_tolerates_capability_gap` |
| G38 | Compat baseline + no gap + empty preview | ✅ | `security.tftest.hcl::compatibility_mode_no_gap_plans_clean_with_empty_preview` |
| G39 | Capability gap across multiple visibilities (counting) | ✅ | `security.tftest.hcl::strict_mode_reports_gaps_across_multiple_visibilities` |

**Global validation coverage: 39 / 39 ≈ 100%.**

## Variable validation blocks

| # | Variable | Validation | Status | Test |
|---|---|---|---|---|
| V01 | `github_owner` | regex (alphanumeric + hyphen, non-edge) | ✅ | `validation.tftest.hcl::rejects_invalid_github_owner_regex` |
| V02 | `github_auth_mode` | enum [app, token] | ✅ | `validation.tftest.hcl::rejects_invalid_auth_mode_enum` |
| V03 | `security_baseline_mode` | enum [strict, compatibility] | ✅ | `validation.tftest.hcl::rejects_invalid_baseline_mode_enum` |

**Variable validation coverage: 3 / 3 ≈ 100%.**

## Per-resource preconditions

| # | Resource | Precondition | Status | Test |
|---|---|---|---|---|
| P01 | `github_repository.repo` | visibility enum valid | ✅ | `preconditions.tftest.hcl::rejects_invalid_visibility_enum` |
| P02 | `github_repository.repo` | public repo requires description | ✅ | `preconditions.tftest.hcl::rejects_public_repo_without_description` |
| P03 | `github_repository_ruleset.branch` | enforcement enum valid | ✅ | `preconditions.tftest.hcl::rejects_invalid_ruleset_enforcement` |
| P04 | `github_repository_ruleset.branch` | `require_code_owner_review` needs `effective_codeowners` (org mode) | ✅ | `preconditions.tftest.hcl::rejects_org_mode_codeowners_required_but_missing` |
| P05 | `github_repository_environment.environment` | `wait_timer` range 0–43200 | ✅ | `preconditions.tftest.hcl::rejects_env_wait_timer_out_of_range` |
| P06 | `github_repository_environment.environment` | protected/custom branch policy exclusivity | ✅ | `preconditions.tftest.hcl::rejects_env_branch_policy_mutually_exclusive` |
| P07 | `github_actions_repository_permissions.actions` | `allowed_actions` enum valid | ✅ | `preconditions.tftest.hcl::rejects_actions_allowed_actions_enum` |
| P08 | `github_actions_repository_permissions.actions` | `selected` requires `allowed_actions_config` | ✅ | `preconditions.tftest.hcl::rejects_actions_selected_without_config` |

**Per-resource precondition coverage: 8 / 8 ≈ 100%.**

## Normalization paths (regression-sensitive)

| # | Path | Status | Test |
|---|---|---|---|
| N01 | `effective_codeowners` synthesis in personal mode | ✅ | `normalization.tftest.hcl::personal_mode_synthesizes_codeowners` |
| N02 | `effective_codeowners` passthrough from explicit YAML | ✅ | `normalization.tftest.hcl::org_mode_explicit_codeowners_plans_clean` |
| N03 | `effective_codeowners` null in org mode with no explicit | ✅ | `preconditions.tftest.hcl::rejects_org_mode_codeowners_required_but_missing` |
| N04 | `security_and_analysis` all-null → null | ✅ | `security.tftest.hcl::no_baseline_no_yaml_collapses_security_to_null` |
| N05 | `security_and_analysis` baseline gated by capability (positive) | ✅ | `security.tftest.hcl::baseline_feature_enabled_when_capability_matches` |
| N06 | `security_and_analysis` explicit YAML overrides baseline | ✅ | `normalization.tftest.hcl::explicit_security_and_analysis_overrides_baseline` |
| N07 | `unmanaged_security_features` forces listed `security_and_analysis` features to null | ✅ | `security.tftest.hcl::unmanaged_secret_features_collapse_security_to_null` |
| N08 | `pages.cname = try(..., null)` (Finding 5 single-arg try regression) | ✅ | `normalization.tftest.hcl::pages_partial_fields_plans_clean` |
| N09 | Pattern block `try()` fixes — partial fields | ✅ | `normalization.tftest.hcl::pattern_blocks_with_only_pattern_field_plans_clean` |
| N10 | `merge_queue` partial fields | ✅ | `normalization.tftest.hcl::merge_queue_with_partial_fields_plans_clean` |
| N11 | `pull_request` partial fields | ✅ | `normalization.tftest.hcl::pull_request_with_only_merge_methods_plans_clean` |
| N12 | `license_template = null` default (Finding 22: MIT removal) | ✅ | `normalization.tftest.hcl::license_template_defaults_null_not_MIT` + default sweep |
| N13 | Branch source ordering (Finding 21) — multi-branch | ✅ | `normalization.tftest.hcl::multi_branch_sources_all_from_default_not_serially` |
| N14 | Fork normalization (source_owner / source_repo) | ✅ | `normalization.tftest.hcl::fork_repo_passes_through_source_fields` |
| N15 | Repo default rulesets applied when no YAML rules | ✅ | `normalization.tftest.hcl::good_minimal_produces_expected_resource_counts` |
| N16 | **All ~28 repo_setting_defaults** (default value sweep) | ✅ | `normalization.tftest.hcl::good_minimal_carries_expected_defaults` |
| CO1 | Org mode honors a non-empty global `repo_default_codeowners` | ✅ | `normalization.tftest.hcl::org_mode_uses_global_codeowners_default` |
| CO2 | Per-repo `codeowners` overrides the global default | ✅ | `normalization.tftest.hcl::org_mode_per_repo_codeowners_overrides_global_default` |
| CO3 | Personal mode honors a non-empty global `repo_default_codeowners` | ✅ | `normalization.tftest.hcl::personal_mode_uses_global_codeowners_default` |
| CO4 | Personal mode with no default synthesizes the bare personal owner | ✅ | `normalization.tftest.hcl::personal_mode_synthesizes_codeowners` |
| CO5 | Org mode with no default retains the ruleset precondition guard | ✅ | `preconditions.tftest.hcl::rejects_org_mode_codeowners_required_but_missing` |
| CO6 | Empty personal default synthesizes; whitespace org default triggers the guard | ✅ | `normalization.tftest.hcl::personal_mode_empty_codeowners_default_synthesizes` + `normalization.tftest.hcl::org_mode_whitespace_codeowners_default_is_rejected` |

**Normalization coverage: 16 / 16 ≈ 100%.**
## `for_each` filter regressions

| # | Filter | Status | Test |
|---|---|---|---|
| F01 | `github_repository_dependabot_security_updates` excludes archived | ✅ | `normalization.tftest.hcl::archived_repo_filters_out_downstream_locals` (transitive) |
| F02 | `github_repository_file.codeowners` excludes archived + null effective | ✅ | `normalization.tftest.hcl::good_minimal_produces_zero_environments_zero_codeowners` |
| F03 | `github_actions_repository_permissions.actions` excludes archived + null actions | ✅ | `normalization.tftest.hcl::archived_repo_filters_out_downstream_locals` |
| F04 | `branches` local excludes archived + empty branch list | ✅ | `normalization.tftest.hcl::archived_repo_filters_out_downstream_locals` |
| F05 | `branch_rulesets` local excludes archived + applies push filter | ✅ | `normalization.tftest.hcl::archived_repo_filters_out_downstream_locals` |
| F06 | `repository_environments` excludes archived + empty envs | ✅ | `normalization.tftest.hcl::good_minimal_produces_zero_environments_zero_codeowners` |
| F07 | `repository_environment_branch_policies` requires `custom_branch_policies == true` | ✅ | `normalization.tftest.hcl::custom_environment_branch_policy_plans_clean` |
| F08 | `repository_environment_variables` requires non-empty variables | ✅ | `normalization.tftest.hcl::good_minimal_produces_zero_environments_zero_codeowners` |
| F09 | `repository_environment_secrets` for_each skips envs with zero declared secret names | ✅ | `normalization.tftest.hcl::good_minimal_produces_zero_environments_zero_codeowners` |
| F10 | Empty-input resilience (every filter survives zero repos) | ✅ | `normalization.tftest.hcl::empty_repo_set_exercises_every_filter_on_zero_input` |

**for_each filter coverage: 10 / 10 ≈ 100%.**

## Edge cases and smoke

| # | Path | Status | Test |
|---|---|---|---|
| E01 | Zero repos (empty fixture) doesn't crash | ✅ | `normalization.tftest.hcl::empty_repo_set_plans_clean` |
| E02 | Archived repo skips branch/ruleset management | ✅ | `normalization.tftest.hcl::archived_repo_plans_clean` |
| E03 | Repo with environments | ✅ | `normalization.tftest.hcl::repo_with_environments_plans_clean` |
| E04 | Repo with explicit rules | ✅ | Transitive via `good-partial-*` and `good-push-ruleset` fixtures |
| E05 | Repo with pages block | ✅ | `normalization.tftest.hcl::pages_partial_fields_plans_clean` |
| E06 | Resource count assertion on good-minimal | ✅ | `normalization.tftest.hcl::good_minimal_produces_expected_resource_counts` |

**Edge case coverage: 6 / 6 ≈ 100%.**

---

## Aggregate

| Layer | Covered | Total | % |
|---|---|---|---|
| Global validation | 39 | 39 | 100% |
| Variable validation | 3 | 3 | 100% |
| Per-resource preconditions | 8 | 8 | 100% |
| Normalization paths | 15 | 15 | 100% |
| for_each filter regressions | 10 | 10 | 100% |
| Edge cases | 6 | 6 | 100% |
| **Overall** | **81** | **81** | **100%** |

## Test run count and artifacts

| Metric | Count |
|---|---|
| `.tftest.hcl` files | 4 |
| `run` blocks total | 55 |
| Fixture directories | 31 |
| Assertions total | 76 |

## Explicitly NOT tested (by design)

The following categories are intentionally excluded. Testing them is either duplicative, impossible with `terraform test`, or out of scope:

| Category | Reason |
|---|---|
| Pass-through resource attributes (`attr = each.value.field` on every resource) | Tested transitively via the normalization layer. The attribute IS the local — testing both is duplicate work. |
| `dynamic` block emission | Same reason. Emits from validated locals; no logic of its own. |
| Ruleset rule sub-attribute pass-through (~20 fields) | Same reason. Tested via `branch_rulesets` local assertions. |
| Apply-time `depends_on` ordering under concurrency | `terraform test` cannot observe real ordering without real apply. Belongs in runner integration tests. |
| Provider authentication against real provider APIs | Not our code. `mock_provider` bypasses real auth intentionally. |
| Provider internal behavior | Not our code. HashiCorp's contract. |
| Backend state locking | Backend is configured by the runner's `backend_override.tf`. |
| `yamldecode` edge cases | Terraform builtin. Not our code. |

This exclusion list is a **deliberate overengineering guard**. Any PR that tries to add tests in these categories should be rejected unless it cites a specific observed regression.

## Coverage tool status

No Codecov. No LCOV. No equivalent for Terraform code. This matrix is the tool. Review it on every framework PR that touches validation, normalization, or resource preconditions.

## Benchmarking against industry practice

| Project | Run blocks | Approach |
|---|---|---|
| `terraform-aws-modules/vpc/aws` | ~30 | Fixture-driven |
| `terraform-google-modules/network` | ~20 | Fixture-driven + integration |
| Gruntwork modules | Few `tftest`, heavy terratest | Integration-first |
| OpenTofu's own test suite | ~50 | Feature coverage |
| **This framework** | **~55** | **Fixture + coverage-matrix driven** |

We're at the upper end of community practice without crossing into overengineering.
