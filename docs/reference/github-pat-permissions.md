# GitHub PAT permissions matrix

**Type**: Reference (Diátaxis). For procedural setup, see [`how-to/setup-github-pat.md`](../how-to/setup-github-pat.md). For rationale, see [`explanation/runner-credentials.md`](../explanation/runner-credentials.md).

This document specifies the minimum fine-grained Personal Access Token permissions required for `github-terraform-runner` to apply the framework against an org. Every row maps a terraform resource the framework manages to the GitHub API endpoint(s) it calls and the fine-grained PAT permission(s) those endpoints require.

The authoritative GitHub source for endpoint-to-permission mappings is the [permissions-required-for-fine-grained-personal-access-tokens](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens) docs page. This document derives from it.

## Minimum viable PAT

For a runner that applies all currently-implemented framework resources, the PAT requires:

| Permission             | Level | Required for |
|------------------------|-------|--------------|
| Metadata               | Read  | All endpoints (forced by GitHub) |
| Administration         | R/W   | Repository settings, rulesets, environments (PUT), dependabot, branch defaults |
| Contents               | R/W   | `github_repository_file` (CODEOWNERS), `github_branch` |
| Actions                | R/W   | `github_actions_repository_permissions`, environment refresh (GET) |
| Environments           | R/W   | Environment internals beyond the create/refresh path |

The above is the baseline. Add **Secrets: R/W** and/or **Variables: R/W** only when an adopting repo's YAML actually declares `environments[].secrets:` or `environments[].variables:`. Until then, declaring those permissions on the PAT widens its blast radius without functional benefit.

## Per-resource matrix

| Terraform resource | API endpoint(s) called | Permission required |
|---|---|---|
| `github_repository` | `POST /orgs/{org}/repos`, `PATCH /repos/{owner}/{repo}` | Administration: Write |
| `github_branch_default` | `PATCH /repos/{owner}/{repo}` (`default_branch`) | Administration: Write |
| `github_branch` | `POST /repos/{owner}/{repo}/git/refs` | Contents: Write |
| `github_repository_file` | `PUT /repos/{owner}/{repo}/contents/{path}` | Contents: Write |
| `github_repository_dependabot_security_updates` | `PUT /repos/{owner}/{repo}/automated-security-fixes` | Administration: Write |
| `github_actions_repository_permissions` | `PUT /repos/{owner}/{repo}/actions/permissions/*` | Actions: Read+Write |
| `github_repository_ruleset` | `POST /repos/{owner}/{repo}/rulesets`, `PATCH /repos/{owner}/{repo}/rulesets/{id}` | Administration: Write |
| `github_repository_environment` (PUT) | `PUT /repos/{owner}/{repo}/environments/{name}` | Administration: Write |
| `github_repository_environment` (GET, refresh) | `GET /repos/{owner}/{repo}/environments/{name}` | **Actions: Read** |
| `github_repository_environment_deployment_policy` | `POST /repos/{owner}/{repo}/environments/{name}/deployment-branch-policies` | Administration: Write |
| `github_actions_environment_secret` | `PUT /repos/{owner}/{repo}/environments/{name}/secrets/{secret_name}` | Secrets: Write |
| `github_actions_environment_variable` | `POST /repos/{owner}/{repo}/environments/{name}/variables` | Variables: Write |

The PUT/GET asymmetry on environments is real and documented: GitHub places `PUT environment` under the **Administration** permission section and `GET environment` under the **Actions** permission section. A PAT with Administration but no Actions can create environments but cannot refresh them. See [`explanation/runner-credentials.md`](../explanation/runner-credentials.md) for the full discussion.

## Repository access scope

The PAT must be scoped to **all repositories owned by the org** (not "Selected repositories") for new repos to inherit access automatically without a per-repo PAT edit. Trade-off discussion is in the explanation doc.

## Expiration

The PAT MUST have an expiration date. Recommended cadence: **90 days**, rotated per [`how-to/setup-github-pat.md`](../how-to/setup-github-pat.md).

## Rules for adding new resource types

When the framework adds a new `github_*` resource:

1. Look up the API endpoint(s) called by the resource in the [terraform-provider-github source](https://github.com/integrations/terraform-provider-github).
2. Look up the required fine-grained permission for each endpoint in [GitHub's permissions table](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens).
3. Add a row to the matrix above.
4. If the new permission is not already in the **Minimum viable PAT** section, add it there with a note about which resource introduced the requirement.
5. If a PUT/GET asymmetry exists (different permission categories for create vs. read), call it out explicitly in the matrix.

## Classic PAT fallback

A classic PAT with the `repo` scope satisfies every endpoint above because `repo` is a coarse super-bucket that covers every per-resource fine-grained permission. Use it only as a break-glass measure during incidents; classic PATs cannot enforce the per-permission separation that fine-grained PATs provide.
