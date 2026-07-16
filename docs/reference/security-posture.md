# Security posture

GitHub secret scanning and push protection are free for public repositories. On private and internal repositories they are paid GitHub Secret Protection features (currently billed per active committer). The defaults therefore keep the free public features on while pinning paid and private/internal features off. Dependabot vulnerability alerts and security updates are free, but independently default off as a client preference; explicitly setting `vulnerability_alerts: true` also defaults omitted `dependabot_security_updates` to true.

For each security feature, the framework applies this precedence: per-repository `unmanaged_security_features` yields `null`; fleet-wide `security_pin_exclude` yields `null`; a non-null YAML `security_and_analysis` boolean is used verbatim; baseline and capability both true yields `true`; otherwise `security_default_status = "disabled"` yields `false`, while `"unmanaged"` yields `null`. After resolving the complete map, the whole block is omitted only when every value is null. Explicit false values remain managed and keep the block present.

`github_security_capabilities` gates only the baseline path. It does not prevent explicit YAML `true` when capability is false. That bypass is intentional: the reviewed YAML edit and PR approval are the sanctioned feature and cost authorization, rather than an entitlement declaration. `unmanaged_security_features` is the per-repository escape hatch; `security_pin_exclude` is its fleet-wide counterpart and takes precedence over YAML; `security_default_status` controls only the final fallback.

Provider issue #3501 can cause `code_security` not to read back and therefore produce a permanent diff. Mock-provider tests verify that excluding it omits its nested block while disabled sibling blocks remain, but cannot verify the real API. Treat this as an accepted external risk and run a real-account, two-plan smoke check during rollout. Some account/repository combinations may also reject a disable PATCH; use per-repository unmanaged features, fleet pin exclusion, or unmanaged fallback as appropriate.

Changing these defaults intentionally creates fleet-wide first-plan diffs, including disabling out-of-band paid features and the independent Dependabot defaults. Every runner must perform and review a plan-only run before any apply.

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
