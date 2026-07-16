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

Commit the non-sensitive settings object as `terraform/org.auto.tfvars` in the runner repository. The reusable workflow copies that file to `framework/terraform/org.auto.tfvars`, where Terraform automatically loads it. At minimum, provide the live display name:

```hcl
org_settings = {
  name = "<live organization display name>"

  security_defaults_for_new_repositories = {
    advanced_security               = false
    secret_scanning                 = false
    secret_scanning_push_protection = false
    dependabot_alerts               = false
    dependabot_security_updates     = false
    dependency_graph                = false
  }
}
```

The restrictive defaults intentionally change member repository creation and Pages permissions to `false`, organization/repository projects to `false`, and web commit signoff to `true`. Owners and administrators are unaffected by member repository-creation restrictions. Explicitly copy any live permissive values that the organization needs to retain.

Leave every field in the nested `org_settings.security_defaults_for_new_repositories` block false unless the organization deliberately opts into that feature and, where applicable, its cost. The block may be omitted when all six defaults remain false.

Create an Actions secret named `ORG_BILLING_EMAIL` in the runner repository. Pass org mode and the secret to the reusable workflow:

```yaml
jobs:
  deploy:
    with:
      github_is_organization: true
    secrets:
      org_billing_email: ${{ secrets.ORG_BILLING_EMAIL }}
```

The reusable workflow exports `TF_VAR_org_billing_email` through `GITHUB_ENV` only when the optional secret is non-empty. Never place the billing address in committed Terraform, tfvars, YAML, logs, or test assertions, and do not map `TF_VAR_org_billing_email` at job level.

`org_billing_email` remains separate from the single `org_settings` object because sensitive values follow the framework's top-level injection pattern: the resource receives the secret directly, while normalized locals contain only non-sensitive settings and remain readable in plans.

## Roll out atomically

Flipping `github_is_organization` to `true` disables automatic bare-org CODEOWNERS synthesis because a bare organization is not a valid GitHub code owner. A configured global `repo_default_codeowners` containing a valid user or team is honored in both modes, and a per-repo `codeowners:` value overrides it. In one runner pull request:

- pass `github_is_organization: true` to the reusable workflow;
- wire the `org_billing_email` reusable-workflow secret;
- add `terraform/org.auto.tfvars`; and
- configure a valid user or team in the global `repo_default_codeowners`, with per-repo `codeowners:` overrides where needed.

The reusable workflow automatically adopts existing organization settings after repository and ruleset adoption and before validation and planning. It imports only when org mode is enabled, `org.auto.tfvars` is present, the billing secret was exported, and the resource is absent from state. Provider 6.12.1 create logic uses `GetOk`, so this import ensures the first operation uses the update path and can pin false values. No manual state splice or runner-side `terraform import` is required.

Import-before-validation follows the existing adoption pattern. Import reads GitHub and records the live organization settings in the backend; it does not update GitHub. A later validation failure therefore leaves a correct, idempotently adopted binding that the next run detects and skips. Under `plan_only`, adoption uses the workflow's ephemeral local backend and cannot modify canonical S3 state.

Before merging the atomic rollout, retain the pre-flight safety check: pull the current state and verify a local no-op plan. Do not apply the resource before adoption has completed.

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
