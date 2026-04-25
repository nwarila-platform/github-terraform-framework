# Runner credentials: design and gotchas

**Type**: Explanation (Diátaxis). For the matrices and procedures themselves, see the [reference](../reference/) and [how-to](../how-to/) directories.

This document explains *why* `github-terraform-runner` authenticates to GitHub with a fine-grained Personal Access Token and to AWS with an OIDC-issued role, what the alternatives were, and the two non-obvious failure modes we have seen in practice.

## Why a fine-grained PAT for GitHub auth

The `github` terraform provider supports two authentication modes:

1. **GitHub App installation** — preferred for enterprise automation. Tokens are short-lived, attestation is per-installation, and an org admin can pre-approve specific repository scopes. Setup requires creating a GitHub App, generating a private key, configuring an installation per repo or org, and storing the App ID, installation ID, and PEM bytes as runner secrets.
2. **Personal Access Token** — direct credential authentication. A single token authenticates as the human who created it. Setup is creating a token in the GitHub UI and pasting its value into a runner secret.

We picked **fine-grained PAT** for the current iteration. The reasoning:

- The runner is operated by a single human owner of a small org. The pre-approval and per-installation isolation that a GitHub App provides solves a problem we do not have.
- A fine-grained PAT can still be scoped narrowly per-permission, which gives most of the benefit of an App's permission isolation without the App-management overhead.
- Setting up a GitHub App and managing its lifecycle (key rotation, installation rollout) is non-trivial work that we have deferred.

The trade-offs we accept:

- The PAT acts on behalf of the owner-human, so audit logs attribute every CI-driven change to that human rather than to a distinct service identity. For a solo-maintained org this is acceptable; for a multi-maintainer org it becomes confusing fast.
- PATs cannot be pre-approved per-repo at org level the way App installations can; they have a binary "all repos" or "selected repos" choice.
- PATs require manual rotation. Apps issue short-lived tokens automatically.

When to revisit: the moment the org gains a second active maintainer, or the moment we want CI activity to surface as a non-human identity in audit logs, we should migrate to a GitHub App. The [`reference/github-pat-permissions.md`](../reference/github-pat-permissions.md) matrix would not change — Apps use the same per-permission model — only the trust mechanism would.

## Why OIDC + IAM role for AWS auth

The runner needs S3 access for two purposes: reading private repo YAML definitions and reading/writing terraform state. The available AWS auth options are:

1. **Long-lived AWS access keys** stored as Actions secrets.
2. **OIDC federation** — GitHub Actions presents its OIDC ID token to AWS STS, which exchanges it for a short-lived role session.

We picked **OIDC federation**. The reasoning:

- Long-lived keys in CI are an audit and rotation burden. They sit in secrets indefinitely; they leak into transcripts and forks; they require periodic rotation.
- OIDC tokens are short-lived (~15 min default), are minted fresh per workflow run, and are bound to the specific repo/branch/job that requested them.
- The trust relationship can be tightened to specific `sub` claims (e.g., `repo:nwarila-platform/github-terraform-runner:ref:refs/heads/main`), eliminating the "role usable from any source" risk that plagues long-lived keys.

The trade-off we accept:

- OIDC requires bootstrap work: configuring the GitHub OIDC provider in AWS, writing a trust policy with the right `sub` and `aud` claims, and creating the role itself. That bootstrap is one-time work, but it is more work than pasting an access key into a secret.

This decision is unlikely to be revisited; OIDC is strictly better than long-lived keys for CI workloads.

## Why the credentials are split across two systems instead of one

GitHub auth and AWS auth are separate concerns:

- GitHub auth is needed to manage GitHub resources (repos, rulesets, environments).
- AWS auth is needed to read the private repo YAMLs from S3 and to read/write terraform state in S3.

These are different trust boundaries (GitHub vs. AWS), different identity providers, and different blast radii on compromise. Combining them — for example, by storing AWS keys in GitHub secrets accessible to the GitHub-side terraform provider — would couple the two boundaries unnecessarily. Splitting them ensures a compromise of one credential does not yield the other.

## Gotcha 1: the GET/PUT permission asymmetry on environments

For weeks we hit a 403 on `GET /repos/{owner}/{repo}/environments/{name}` while `PUT` to the same path succeeded. The PAT had **Administration: Read and write** plus **Environments: Read and write**, which we expected to cover both operations. It does not.

GitHub's [permissions table](https://docs.github.com/en/rest/authentication/permissions-required-for-fine-grained-personal-access-tokens) places the two operations under **different** permission categories:

- `PUT /repos/{owner}/{repo}/environments/{name}` is documented under **Administration: Write**.
- `GET /repos/{owner}/{repo}/environments/{name}` is documented under **Actions: Read**.

A PAT with Administration but no Actions can therefore create environments but cannot refresh them. Terraform's `github_repository_environment` resource calls the GET on every refresh; without Actions the apply succeeds once and every subsequent plan dies on refresh.

The classic-PAT `repo` scope works because `repo` is a coarse super-bucket that covers both the Administration-tagged and Actions-tagged endpoints. Fine-grained PATs do not get that coarse coverage.

Implications:

- The framework's PAT requirement matrix in [`reference/github-pat-permissions.md`](../reference/github-pat-permissions.md) carries **Actions: Read and write**. This is non-obvious to anyone setting up a PAT for the first time.
- Future GitHub API additions may introduce more such asymmetries. The matrix's "Rules for adding new resource types" section explicitly mandates checking for asymmetries.

A 403 from GitHub on a fine-grained PAT also returns an `X-Accepted-GitHub-Permissions` response header naming the exact permission demanded. When debugging, capture it with `curl -i` rather than guessing.

## Gotcha 2: S3 `ListBucket` and the `max-keys` condition

The runner workflow downloads private repo YAMLs from S3 with `aws s3 sync`. `sync` calls `ListObjectsV2` to enumerate keys before fetching them, which requires `s3:ListBucket` on the role.

The original IAM policy granted `s3:ListBucket` correctly but qualified it with `NumericLessThanEquals s3:max-keys = 50` as anti-enumeration hardening. AWS CLI's default `ListObjectsV2` request specifies **`max-keys=1000`** per page, which fails the `<=50` condition. The result was a generic AccessDenied error: *"User is not authorized to perform: s3:ListBucket ... because no identity-based policy allows the s3:ListBucket action."* That message implies "you have no `s3:ListBucket` allow at all," not the actual cause "your `s3:ListBucket` allow has a condition that the request does not satisfy."

The fix was removing the `NumericLessThanEquals` condition. With ~5 YAML files in the prefix, the max-keys constraint did not provide meaningful anti-enumeration value; the prefix-scope condition (`StringEquals s3:prefix`) does the actual work.

Implications:

- The reference IAM policy intentionally has no `max-keys` condition. Future operators should not re-add it.
- AWS's IAM denial messages do not always discriminate between "no allow" and "allow with failed condition." When debugging a `ListBucket` 403, suspect a condition on the existing allow before assuming there is no allow.

## Why no GitHub App today, and when to revisit

Setting up a GitHub App for this runner would yield: short-lived tokens, an installation-scoped trust boundary, audit-log entries attributed to a non-human service identity, and elimination of the manual rotation cadence. The setup cost is creating the App, storing its private key, registering its installation, and updating the runner workflow's auth path.

We deferred that work because:

- The org has one human maintainer, so the audit-log clarity benefit is small.
- The manual PAT rotation cadence is acceptable when there is one token to rotate.
- The fine-grained PAT model already gives most of the per-permission isolation that an App would.

We expect to revisit when:

- A second active maintainer joins the org.
- We hire or onboard a contractor whose CI activity must be distinguishable from the maintainer's.
- We integrate with downstream systems that require non-human-attributable audit trails.

When that day comes, the migration involves: creating the App, granting it an installation on the org, updating the runner workflow to use App-mode auth (`var.github_auth_mode = "app"` plus the three `github_app_auth` variables), and rotating the existing PAT to a short overlap window before removing it.
