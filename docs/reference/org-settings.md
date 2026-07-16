# Organization settings reference

**Type**: Reference (Diátaxis). For rollout instructions, see [`how-to/manage-org-settings.md`](../how-to/manage-org-settings.md).

The framework can opt in to managing the GitHub organization settings surface with `github_organization_settings.org`. The default is unmanaged: `org_settings = null` produces no resource. This resource is valid only when `github_is_organization = true`.

For reusable-workflow runners, pass the boolean `github_is_organization` input and the optional `org_billing_email` secret to `.github/workflows/reusable-terraform-deploy.yaml`. Commit only the non-sensitive `org_settings` object in the runner as `terraform/org.auto.tfvars`; the workflow overlays it at `framework/terraform/org.auto.tfvars` for automatic loading.

Existing callers remain semantically unchanged when they do not opt in. An omitted `github_is_organization` input exports explicit `false`, matching the Terraform variable default. An omitted `org_billing_email` secret writes nothing to `GITHUB_ENV`, leaving `TF_VAR_org_billing_email` absent so Terraform retains its `null` default. An absent runner `terraform/org.auto.tfvars` makes the conditional overlay a no-op.

## Inputs

### `org_settings`

`org_settings` is the single non-sensitive organization-settings object. Its `name` field is required; every other field has an explicit safe default. The framework normalizes all 25 non-sensitive provider attributes from this object before mapping them one-to-one into the resource.

| Field | Type | Default | Contract |
|---|---|---:|---|
| `name` | string | required | Non-empty organization display name; must match live state unless intentionally changing it. |
| `description` | string | `""` | Must match the live profile value. |
| `company` | string | `""` | Must match the live profile value. |
| `blog` | string | `""` | Must match the live profile value. |
| `email` | string | `""` | Must match the live profile value. |
| `location` | string | `""` | Must match the live profile value. |
| `twitter_username` | string | `""` | Must match the live profile value. |
| `default_repository_permission` | string | `"read"` | One of `read`, `write`, `admin`, or `none`. |
| `members_can_create_repositories` | bool | `false` | Restrictive, expense-free default. |
| `members_can_create_public_repositories` | bool | `false` | Restrictive, expense-free default. |
| `members_can_create_private_repositories` | bool | `false` | Restrictive, expense-free default. |
| `members_can_create_internal_repositories` | bool | `false` | Restrictive default. `true` on a Free organization can permadiff because the provider sends it only for Enterprise organizations. |
| `members_can_create_pages` | bool | `false` | Restrictive default. |
| `members_can_create_public_pages` | bool | `false` | Restrictive default. |
| `members_can_create_private_pages` | bool | `false` | Restrictive default. |
| `members_can_fork_private_repositories` | bool | `false` | Restrictive default. |
| `has_organization_projects` | bool | `false` | Projects-off default. |
| `has_repository_projects` | bool | `false` | Projects-off default. |
| `web_commit_signoff_required` | bool | `true` | Commit-signoff default. |
| `security_defaults_for_new_repositories` | object | `{}` | Nested new-repository security defaults; every nested feature defaults to `false`. |

These restrictive `members_can_*` defaults can change existing live `true` values on the first apply. Organization owners and administrators are not constrained by member repository-creation restrictions. A runner that needs permissive behavior must set those values explicitly.

### `org_billing_email`

`org_billing_email` is a sensitive string with default `null`. It must be trimmed and non-empty whenever `org_settings` is managed. Supply it as `TF_VAR_org_billing_email` from a GitHub Actions secret such as `ORG_BILLING_EMAIL`; never commit it. It is deliberately the top-level-sensitive exception to the single-object contract: credentials and other sensitive values are injected only at the resource attribute, never included in normalized locals. This keeps `local.organization_settings` non-sensitive and its plan diffs readable.

### `org_settings.security_defaults_for_new_repositories`

This nested object defaults to `{}` and every feature defaults to `false`. A `true` value is a deliberate feature or paid-feature opt-in.

| Field | Default | Expense posture |
|---|---:|---|
| `advanced_security` | `false` | Paid: GitHub Advanced Security / Code Security. |
| `secret_scanning` | `false` | Paid on private repositories through Secret Protection. |
| `secret_scanning_push_protection` | `false` | Paid on private repositories through Secret Protection. |
| `dependabot_alerts` | `false` | Free, but disabled because Dependabot is unused under the ratified posture. |
| `dependabot_security_updates` | `false` | Free, but disabled under the ratified posture. |
| `dependency_graph` | `false` | Free, but disabled because it feeds Dependabot. |

## Validation contract

Plan is rejected when any of these conditions is true:

1. V1: `org_settings` is managed for a personal account (`github_is_organization = false`).
2. V2: managed settings have a null, empty, or whitespace-only `org_billing_email`.
3. V2b: managed settings have an empty or whitespace-only `name`.
4. V3: `org_billing_email` is set while `org_settings` is unmanaged.
5. V4: `default_repository_permission` is not `read`, `write`, `admin`, or `none`.

There is no dangling-security validation: security defaults are nested inside `org_settings`, so configuring them while organization settings are unmanaged is structurally impossible.

## Provider 6.12.1 behavior

The resource explicitly assigns all 26 managed attributes: billing email, seven profile strings, twelve behavioral settings, and six new-repository security defaults. Omitting an attribute is unsafe because Read returns all 26 attributes.

- Create uses `GetOk`. Configured `false` booleans and empty strings are not sent, so create cannot pin the safe false defaults.
- Update uses `HasChange`, then sends changed booleans from `Get`, so read-back drift from `true` to configured `false` is corrected.
- Changed strings are additionally guarded by `GetOk`. Terraform therefore cannot clear a non-empty live string to `""`; clear it in the GitHub UI first or the configuration will permadiff.
- Delete PATCHes `billing_email` to the hardcoded `email@example.com`. The resource uses `prevent_destroy = true`; decommission with state removal, never destroy.
- The provider writes `BillingEmail` and the other fields verbatim to provider logs at `[DEBUG]`. Terraform sensitivity does not redact provider logs. Never use `TF_LOG=DEBUG` or `TF_LOG=TRACE` for organization-settings runs, and do not retain provider debug logs in CI.

Because create cannot transmit false values, the reusable workflow automatically imports the live organization before its first validation and plan when org mode, the overlaid org tfvars file, and the billing variable are all present. It skips adoption when the state already contains the resource. Import reads GitHub and records the live settings in the initialized backend without changing GitHub; a later validation failure can be corrected and retried safely. Under `plan_only`, the initialized backend is ephemeral and local. The first live plan must also be watched for API omissions or plan-gated fields that could cause a read-back permadiff.

The runner rollout must be atomic: enable the workflow's `github_is_organization` input, wire its `org_billing_email` secret, add `terraform/org.auto.tfvars`, and add explicit `codeowners:` entries to every repository YAML whose rulesets require code-owner review. Org mode disables CODEOWNERS auto-synthesis.

## `prevent_destroy` and count transitions

P4 audit result (recorded 2026-07-16, Terraform 1.15.4, offline reproduction with a counted
`terraform_data` resource in local state, `prevent_destroy = true`, count flipped 1 → 0):

```text
Plan: 0 to add, 0 to change, 1 to destroy.
Error: Instance cannot be destroyed
Resource terraform_data.x[0] has lifecycle.prevent_destroy set, but the plan calls for this
resource to be destroyed. To avoid this error and continue with the plan, either disable
lifecycle.prevent_destroy or reduce the scope of the plan using the -target option.
```

Terraform 1.15.4 BLOCKS the destroy plan on a count 1 → 0 transition while
`prevent_destroy` is set — reverting the opt-in (`org_settings = null`) fails the plan rather
than invoking the provider's destructive Delete. The supported decommission procedure is
nevertheless always:

```sh
terraform state rm 'github_organization_settings.org[0]'
```

Never remove the opt-in or run a destroy/count-flip while the resource remains in state.
