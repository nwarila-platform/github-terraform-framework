# How to manage organization settings

**Type**: How-to (Diátaxis). For the complete input and provider behavior contract, see [`reference/org-settings.md`](../reference/org-settings.md).

Use this procedure only for an organization runner. Personal-account runners must leave `org_settings = null`.

## Capture the live settings

Read the current organization before writing runner configuration:

```sh
gh api orgs/<org>
```

Record the organization display name, all six other profile strings, default repository permission, member permissions, project settings, and web commit signoff setting. Every non-empty profile string must be copied exactly into `org_settings`. Provider 6.12.1 cannot clear a non-empty profile string to `""`; clear it in the GitHub UI first if removal is intentional.

## Configure the runner

Set `github_is_organization = true` and define `org_settings`. At minimum, provide the live display name:

```hcl
github_is_organization = true

org_settings = {
  name = "<live organization display name>"
}
```

The restrictive defaults intentionally change member repository creation and Pages permissions to `false`, organization/repository projects to `false`, and web commit signoff to `true`. Owners and administrators are unaffected by member repository-creation restrictions. Explicitly copy any live permissive values that the organization needs to retain.

Leave every field in `org_security_defaults_for_new_repos` false unless the organization deliberately opts into that feature and, where applicable, its cost.

Create an Actions secret named `ORG_BILLING_EMAIL` in the runner repository. Export it to Terraform as `TF_VAR_org_billing_email` in the workflow environment:

```yaml
env:
  TF_VAR_org_billing_email: ${{ secrets.ORG_BILLING_EMAIL }}
```

Never place the billing address in committed Terraform, tfvars, YAML, logs, or test assertions.

## Import before the first plan

Import is required. Provider 6.12.1 create logic uses `GetOk`, so configured false booleans are not sent on create. Import ensures the first operation uses the update path and can pin false values:

```sh
terraform import 'github_organization_settings.org[0]' <org-login>
```

Do not apply the resource before this import.

## Review the first plan

Review every one of the 26 managed attributes. Expected diffs from the safe defaults can include:

- `members_can_create_*`: `true` to `false`
- `has_organization_projects` and `has_repository_projects`: `true` to `false`
- `web_commit_signoff_required`: `false` to `true`

Confirm that all profile strings match the live organization. Confirm that all six new-repository security defaults are false unless a paid or feature opt-in is deliberate. Watch the first live plan and subsequent read-back for API omissions or plan-gated fields that could produce a permadiff.

Never run organization-settings workflows with `TF_LOG=DEBUG` or `TF_LOG=TRACE`. Provider 6.12.1 logs the billing email verbatim at debug level, and CI must not retain provider debug logs.

## Decommission safely

Provider Delete rewrites the organization billing email to `email@example.com`. Never destroy the resource and never disable the opt-in while it remains in state. Remove only Terraform's state binding:

```sh
terraform state rm 'github_organization_settings.org[0]'
```

After state removal, remove the runner inputs and secret. The organization settings remain unchanged in GitHub.
