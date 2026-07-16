# github-terraform-framework

Terraform framework for managing GitHub repositories, rulesets, security defaults, and shared account-level governance as code.

This framework is a **root module** consumed by [github-terraform-runner](../github-terraform-runner). The runner materializes this repo into its `_workspace/` directory, overlays backend config via `backend_override.tf`, and runs `terraform init && terraform apply`.

## Versioning and CLI pinning contract

This framework pins an **exact** Terraform CLI version via `required_version` in [terraform/versions.tf](terraform/versions.tf). Downstream consumers must:

1. **Pin the framework by commit SHA**, not by branch or tag. A branch pin would let an unreviewed framework change land in the consumer silently.
2. **Review framework changes in a PR against the consuming repo**. When the framework updates — including any change to `required_version` — the consumer opens a PR that bumps the pinned SHA. CI in the consumer runs against the new SHA.
3. **Match the pinned Terraform CLI version locally and in CI**. The framework is tested against exactly one CLI version. Divergence is a bug, not a warning.

If `required_version` changes, the commit message on the framework side must flag it explicitly so the downstream PR catches the CLI upgrade.

## Repository YAML schema

Repository definitions live in `terraform/repos/public/*.yml` and `terraform/repos/private/*.yml`. Allowed top-level keys are declared in `local.allowed_repo_keys` ([terraform/30-locals.tf](terraform/30-locals.tf)); unknown keys (including at nested levels) fail plan via `terraform_data.framework_validation`.

### Constraints

- **Seed content is required for branch management.** If a repo sets `auto_init: false`, it must also configure either a `template` or a `fork` source. Otherwise `github_branch_default` will fail at apply time with a provider-level error because there is no default branch to rename. The framework does not pre-validate this — the provider error is adequate.
- **`allow_forking` is not supported.** The key is rejected at the unknown-top-level-key stage. The setting is org-only and not currently managed by a provider-backed resource in this framework; accepting it would be a silent no-op, which is worse than rejecting it. Revisit if the framework grows explicit org-level management.
- **`require_code_owner_review` requires an effective CODEOWNERS source.** A per-repo `codeowners: |` value overrides the global `var.repo_default_codeowners`, which is honored in both organization and personal-account modes. Org mode disables automatic bare-org synthesis because a bare organization is not a valid GitHub code owner; configure the global default with a valid user or team, or use a per-repo override. Personal-account mode synthesizes `* @<github_owner>` when neither source is set. The CODEOWNERS file is provisioned on the default branch, and rulesets depend on it landing first.

## Authentication modes

The `github` provider supports two authentication modes, selected by `var.github_auth_mode`:

- `app` — GitHub App installation. Preferred for enterprise automation. Requires `var.github_app_auth = { id, installation_id, pem_file }`.
- `token` — Classic or fine-grained PAT. Break-glass / bootstrap only. Requires `var.github_token`.

Exactly one of `github_token` / `github_app_auth` must be set. Misconfiguration is caught by `terraform_data.framework_validation` before any resource is touched.

For the **fine-grained PAT permission matrix** (which permission each managed resource requires, the GET/PUT asymmetry on environments, and the rotation procedure), see [`docs/reference/github-pat-permissions.md`](docs/reference/github-pat-permissions.md) and [`docs/how-to/setup-github-pat.md`](docs/how-to/setup-github-pat.md).

## Documentation

This repository follows the [Diátaxis](https://diataxis.fr) framework, adopted org-wide by [ADR-0002](docs/decision-records/org/0002-adopt-diataxis-documentation-framework.md). Long-form documentation lives under [`docs/`](docs/) split into reference, how-to, and explanation quadrants. ADRs live at [`docs/decision-records/`](docs/decision-records/) per [ADR-0001](docs/decision-records/org/0001-use-architecture-decision-records.md), split into `org/` (mirror of the nwarila-platform baseline), `template/` (inherited Terraform framework decisions), and `repo/` (repository-specific, currently empty).

Start at [`docs/README.md`](docs/README.md) for the index. The current `DESIGN.md` predates ADR-0002 and is deferred for a separate re-shelving pass.

## Security baseline

The framework models GitHub security features as a **visibility-keyed capability matrix** against a **desired baseline**:

- `var.github_security_capabilities` — what the owner's plan supports, declared per visibility (`public`, `private`, `internal`). Fully required: every feature for every visibility. Default matches GitHub Free.
- `var.security_baseline` — what the framework wants enabled, per visibility. Default is an opinionated enterprise baseline.
- `var.security_baseline_mode` — `strict` fails plan when the baseline demands a feature the capabilities don't support; `compatibility` emits an advisory preview via a `check` block and leaves unsupported features unmanaged. Default is `compatibility` for non-breaking rollout. Flip to `strict` in the next tagged release after remediating any preview warnings.

A repository YAML may set `unmanaged_security_features` to force individual `security_and_analysis` features to Terraform `null`, even when the baseline or an explicit `security_and_analysis` value would otherwise manage them. This is different from `security_and_analysis.<feature>: false`: `false` manages the disabled state and still PATCHes the provider, while `unmanaged_security_features` omits the feature from the provider payload.

```yaml
example-private-repo:
  visibility: private
  unmanaged_security_features:
    - secret_scanning
    - secret_scanning_push_protection
```

These variables follow the Packer-coherence style: fully typed, fully required, zero `optional()`.

## Regression testing

The framework ships a `terraform test` suite under [terraform/tests/](terraform/tests/) that exercises the validation layer against a set of fixture YAML directories. Tests run offline via `mock_provider` blocks — no real GitHub API calls, no real state.

**Run the suite:**

```bash
cd terraform
terraform init -backend=false
terraform test
```

**What the suite covers:**

- **Positive case:** `good-minimal` — asserts `output.validation_errors` is empty for a clean YAML fixture.
- **Unknown key rejection:** top-level typo (`descripton`), nested typo (`actions.enable`), and the intentionally-rejected `allow_forking`.
- **Duplicate repository keys:** same repo name declared in both `public/` and `private/` must fail plan instead of silently collapsing.
- **Unsupported push rulesets:** a push-target rule on a public repo (or any visibility when `github_supports_push_rulesets=false`) must fail plan.
- **Auth config:** token mode with no token, app mode with no app_auth, and both sources set simultaneously must all fail.
- **Security baseline:**
  - Strict mode with a capability gap fails plan.
  - Compatibility mode with the same gap does NOT fail plan but populates `output.security_capability_gap_preview` so operators can see what a strict flip would break.

**Adding new cases:**

1. Create a new fixture directory under `terraform/tests/fixtures/<case-name>/` with `public/` and/or `private/` subdirectories containing one or more YAML files.
2. Add a `run` block to [terraform/tests/validation.tftest.hcl](terraform/tests/validation.tftest.hcl) that sets `repo_yaml_path = "tests/fixtures/<case-name>"` and either asserts on `output.validation_errors` (positive) or uses `expect_failures = [terraform_data.framework_validation]` (negative for global errors) / the specific resource address (negative for per-resource preconditions).
3. Run `terraform test` to verify the new case passes.

Because the fixture path is selected by `var.repo_yaml_path` (default `repos`), the production code path is unchanged — tests just swap the variable.

## Validation layering

- **Global invariants** (duplicate repo keys, unknown nested YAML keys, unsupported push rulesets, auth config, strict-mode capability gaps) aggregate into `local.global_validation_errors` and are enforced by a single precondition on `terraform_data.framework_validation`.
- **Per-resource invariants** (visibility enum, ruleset enforcement, env wait_timer, actions allowed_actions enum, CODEOWNERS present when required) live as `lifecycle.precondition` blocks on the relevant resources so error messages point at specific resource addresses.
- **One intentional advisory exception:** `check "security_baseline_preview"` emits a warning listing capability gaps in compatibility mode. This is a preview for the strict-mode flip, not an enforcement point.
