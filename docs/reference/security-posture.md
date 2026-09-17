# Security posture

GitHub secret scanning and push protection are free for public repositories. On private and internal repositories they are paid GitHub Secret Protection features (currently billed per active committer). The desired create-time payload therefore keeps the free public features on while setting paid and private/internal features false. Dependabot vulnerability alerts are also declared false at creation. Dependabot **security updates are not managed per repository at all** (removed 2026-07-19): this org uses Renovate exclusively for dependency updates, and the organization-level `dependabot_alerts` / `dependabot_security_updates` defaults for new repositories are both pinned false.

For each feature in the desired create-time `security_and_analysis` payload, the framework applies this precedence: per-repository `unmanaged_security_features` yields `null`; fleet-wide `security_pin_exclude` yields `null`; a non-null YAML boolean is used verbatim; baseline and capability both true yields `true`; otherwise `security_default_status = "disabled"` yields `false`, while `"unmanaged"` yields `null`. After resolving the complete map, the whole block is omitted only when every value is null. Explicit false values keep the create-time block present.

`github_security_capabilities` gates only the baseline path. It does not prevent explicit YAML `true` when capability is false. That bypass is intentional: the reviewed YAML edit and PR approval are the sanctioned feature and cost authorization, rather than an entitlement declaration. `unmanaged_security_features` controls the per-repository create-time payload; `security_pin_exclude` is its fleet-wide counterpart and takes precedence over YAML; `security_default_status` controls only the final fallback. Neither omission control replaces the lifecycle ignore, and neither covers `vulnerability_alerts`.

Terraform declares `security_and_analysis` and `vulnerability_alerts` when it creates a repository, but it intentionally ignores both after creation because GitHub's enforced organization security configuration owns them. Post-create drift in advanced security, code security, all four secret-scanning settings, and Dependabot alerts is therefore absent from Terraform plans and from the Terraform drift detector, and Terraform will not remediate it. Audit and remediation for those settings must occur at the organization-security-configuration layer.

Provider issue #3501 can cause `code_security` not to read back. Mock-provider tests verify create-time normalization but cannot verify the real API; a future repository create can still fail if the enforced organization configuration rejects create-time values.

## Repository forking

The framework manages `allow_forking` according to repository visibility and ownership:

| Repository | Omitted YAML default |
|---|---:|
| Public | `true` |
| Internal | `false` |
| Organization-owned private | `false` |
| Personal-account private | `null` (API field omitted) |

An explicit YAML value overrides these defaults, except that explicit `allow_forking: false` is rejected for public repositories. Forking of public repositories is not restrictable on github.com; attempting to manage it as false can produce a 422 response or a permanent diff when the API reads it back as true. Explicit values on personal-account private repositories pass through, but API acceptance remains unverified and needs a live one-repository test.

The material fork risk is workflow execution at the runner layer. Self-hosted dynamic ephemeral runners are deliberately used on all repositories, including public repositories, with these controls in priority order:

1. Set fork-pull-request workflow approval to its strictest policy: require approval for all outside contributors before any fork-PR workflow runs.
2. Enable runner groups for public repositories only where intended, and restrict those groups to selected repositories and workflows.
3. Keep the default `GITHUB_TOKEN` read-only, never combine `pull_request_target` with checkout of pull-request head code, and pin actions by full commit SHA.
4. Use ephemeral single-use runners, egress NetworkPolicy, and OIDC instead of long-lived secrets at the cluster layer.

## Removing an `actions:` block LOOSENS policy

Deleting a repository's `actions:` block from its YAML destroys the
`github_actions_repository_permissions` resource, and the provider's delete path
resets the repository to `allowed_actions: all` with Actions enabled. Un-declaring
an Actions policy therefore makes the repository **more** permissive, not neutral.

To tighten or retire a policy, change the declared values (for example set
`allowed_actions: all` explicitly) rather than removing the block, so the intent is
visible in review and the live result matches the diff.
