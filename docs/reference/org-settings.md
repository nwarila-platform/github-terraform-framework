# Organization settings reference

**Type**: Reference (Diátaxis). For rollout instructions, see [`how-to/manage-org-settings.md`](../how-to/manage-org-settings.md).

The framework can opt in to managing the GitHub organization settings surface with `github_organization_settings.org`. The default is unmanaged: `org_settings = null` produces no resource. This resource is valid only when `github_is_organization = true`.

## Inputs

### `org_settings`

`org_settings` is an object. Its `name` field is required; every other field has an explicit safe default.

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

These restrictive `members_can_*` defaults can change existing live `true` values on the first apply. Organization owners and administrators are not constrained by member repository-creation restrictions. A runner that needs permissive behavior must set those values explicitly.

### `org_billing_email`

`org_billing_email` is a sensitive string with default `null`. It must be trimmed and non-empty whenever `org_settings` is managed. Supply it as `TF_VAR_org_billing_email` from a GitHub Actions secret such as `ORG_BILLING_EMAIL`; never commit it. Keeping this field outside `org_settings` leaves non-sensitive organization-setting plan diffs readable.

### `org_security_defaults_for_new_repos`

This non-null object defaults to `{}` and every feature defaults to `false`. A `true` value is a deliberate feature or paid-feature opt-in.

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
6. V5: any security default is enabled while `org_settings` is unmanaged. This prevents an explicit paid opt-in from silently becoming a no-op.

## Provider 6.12.1 behavior

The resource explicitly assigns all 26 managed attributes: billing email, seven profile strings, twelve behavioral settings, and six new-repository security defaults. Omitting an attribute is unsafe because Read returns all 26 attributes.

- Create uses `GetOk`. Configured `false` booleans and empty strings are not sent, so create cannot pin the safe false defaults.
- Update uses `HasChange`, then sends changed booleans from `Get`, so read-back drift from `true` to configured `false` is corrected.
- Changed strings are additionally guarded by `GetOk`. Terraform therefore cannot clear a non-empty live string to `""`; clear it in the GitHub UI first or the configuration will permadiff.
- Delete PATCHes `billing_email` to the hardcoded `email@example.com`. The resource uses `prevent_destroy = true`; decommission with state removal, never destroy.
- The provider writes `BillingEmail` and the other fields verbatim to provider logs at `[DEBUG]`. Terraform sensitivity does not redact provider logs. Never use `TF_LOG=DEBUG` or `TF_LOG=TRACE` for organization-settings runs, and do not retain provider debug logs in CI.

Because create cannot transmit false values, rollout must import the live organization before the first plan/apply. The first live plan must also be watched for API omissions or plan-gated fields that could cause a read-back permadiff.

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
