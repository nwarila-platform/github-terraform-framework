# Patch & Analysis Plan

## Purpose

This document turns the adversarial review into an implementation plan that can be tracked in-repo.

Scope for this pass:

- fix the critical and high-confidence flaws identified in the review
- make verification artifacts real and commit-friendly
- leave larger design changes as explicit follow-up work instead of mixing them into the first hardening patch

## Findings In Scope

1. Branch fan-out can block protections from landing.
   `github_repository_ruleset.branch` and `github_repository_file.codeowners` currently wait on the full `github_branch.branches` graph, so one broken non-default branch can strand a newly created repository without rulesets or CODEOWNERS.

2. Nested validation is incomplete.
   The framework still accepts unchecked nested objects under rulesets, which means some typos can silently degrade policy instead of failing plan.

3. Duplicate repository names can bypass detection inside a single YAML file.
   The current duplicate check happens after `yamldecode()`, which is too late to catch repeated top-level keys in the same document.

4. The documented test suite is not actually tracked by git.
   `terraform/tests/` exists locally, but the current root `.gitignore` ignores it, so the README overstates the repo's real regression coverage.

5. Dependency locking is incomplete.
   The configuration requires the `hashicorp/time` provider, but the tracked lockfile does not currently pin it.

## Patch Sequence

### Phase 0: Validation Prerequisite

Before relying on execution-based verification, run the framework with a compatible Terraform CLI.

Current local blocker observed during review:

- local CLI: `Terraform v1.13.2`
- framework requirement: `required_version = "1.14.3"`

Plan for this patch set:

- validate with Terraform `1.14.3`
- defer any `required_version` range change to a separate decision, because that alters the runner contract rather than the reviewed flaws themselves

### Phase 1: Protect The Protection Path

Goal:

- ensure a failed secondary branch does not prevent default protections from landing

Files:

- `terraform/41-resources-gitlab.tf`
- optionally `terraform/30-locals.tf` if a narrower dependency shape is easier to express via new locals

Planned change:

- remove the broad dependency from `github_repository_ruleset.branch` to the entire `github_branch.branches` resource set
- remove the broad dependency from `github_repository_file.codeowners` to the entire `github_branch.branches` resource set
- keep ordering on:
  - repository creation
  - default-branch rename
  - eventual-consistency delay after rename
- preserve the explicit dependency from rulesets to the CODEOWNERS file

Acceptance criteria:

- rulesets still wait for CODEOWNERS when code-owner review is enabled
- a failure creating an extra branch does not block CODEOWNERS or repository rulesets
- the dependency graph no longer contradicts the comment that branch failures should not cascade

### Phase 2: Close Nested Validation Gaps

Goal:

- fail closed for still-unchecked nested ruleset objects

Files:

- `terraform/30-locals.tf`
- `terraform/tests/validation.tftest.hcl`
- new fixtures under `terraform/tests/fixtures/`

Planned change:

- extend unknown-key validation to cover:
  - `rules[].rules.required_deployments`
  - `rules[].rules.required_code_scanning`
  - `rules[].rules.required_code_scanning.required_code_scanning_tool[]`
  - `rules[].rules.file_path_restriction`
  - `rules[].rules.file_extension_restriction`
  - `rules[].rules.max_file_size`
  - `rules[].rules.max_file_path_length`
- add targeted negative fixtures for each newly validated structure or grouped coverage where the error path remains specific

Acceptance criteria:

- typos in the newly covered nested objects fail at the framework validation layer
- a plan can no longer silently accept malformed nested rule objects and fall back to permissive defaults

### Phase 3: Fix Same-File Duplicate Detection

Goal:

- detect repeated repository names before YAML decoding collapses them

Files:

- `terraform/30-locals.tf`
- `terraform/tests/validation.tftest.hcl`
- one or more fixtures under `terraform/tests/fixtures/`
- optional helper script if Terraform-native parsing proves too brittle

Planned change:

- add a raw-file duplicate-key detection pass for top-level repository names
- keep the existing cross-file duplicate protection
- prefer a Terraform-native implementation if it stays readable and deterministic
- if that becomes too fragile, introduce a minimal tracked helper and invoke it only for duplicate detection

Acceptance criteria:

- duplicate repository names in two files fail plan
- duplicate repository names in one file also fail plan
- the failure message makes it clear which file or repo key caused the collision

### Phase 4: Make Verification Artifacts Real

Goal:

- align the repo's tracked contents with its documented validation story

Files:

- `.gitignore`
- `terraform/.terraform.lock.hcl`
- `README.md`
- `terraform/tests/**`

Planned change:

- allowlist `terraform/tests/**` in the repo ignore rules so the test suite is commit-able
- ensure `terraform/.terraform.lock.hcl` includes `hashicorp/time`
- update README statements that describe regression testing so they match the tracked repo state

Acceptance criteria:

- `git ls-files` includes the test suite
- the lockfile pins all declared providers
- the README no longer claims coverage that only exists in ignored local files

## Analysis Plan

### Review Method

For each phase, verify three things:

1. The flaw is reproducible in a fixture or by direct source inspection.
2. The patch removes the failure mode without widening behavior elsewhere.
3. The fix is reflected in documentation and tracked tests where practical.

### Verification Bar

Minimum validation target for the patch series:

1. `terraform fmt -check`
2. `terraform validate`
3. `terraform test`
4. targeted review of the changed dependency edges in the plan graph by source inspection

If the runner repository owns additional policy scanning, note that linkage in the final documentation update instead of pretending it runs here.

### Test Additions

Add or confirm coverage for:

- bad nested keys in each newly validated ruleset subobject
- duplicate repo names within a single YAML file
- branch-failure isolation behavior, if feasible with mocks
- tracked positive fixture paths still planning clean after validation changes

### Patch Boundaries

Keep this hardening pass focused.

Do not mix in these follow-up items unless explicitly requested:

- changing `required_version` from an exact pin to a range
- GitHub App authentication redesign
- broader security-baseline model changes
- house-style refactors unrelated to the reviewed flaws

## Deliverables

- code changes for the four in-scope findings
- tracked regression fixtures and `.tftest.hcl` updates
- README updates for verification accuracy
- refreshed provider lockfile
- a short closeout summary mapping each finding to its fix

## Exit Criteria

This patch plan is complete when:

- each in-scope finding has either a merged fix or an explicit documented deferral
- the test suite is tracked in git
- all declared providers are pinned in the lockfile
- verification can be run on a compatible Terraform version without undocumented local-only files
