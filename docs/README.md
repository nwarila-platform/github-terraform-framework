# Documentation

This directory follows the [Diátaxis](https://diataxis.fr) framework, adopted org-wide by [ADR-0002](https://github.com/nwarila-platform/.github/blob/main/docs/decision-records/0002-adopt-diataxis-documentation-framework.md). Each document lives in exactly one quadrant.

| Quadrant | Purpose | When to read |
|---|---|---|
| [Reference](reference/) | Look up facts | "What permission does X need?" |
| [How-to](how-to/) | Solve a specific problem | "How do I rotate the PAT?" |
| [Explanation](explanation/) | Understand the rationale | "Why fine-grained PAT instead of a GitHub App?" |
| Tutorials | Learn by doing | (not currently populated) |

## Reference

- [GitHub PAT permissions matrix](reference/github-pat-permissions.md) — per-resource-type permission requirements for the fine-grained PAT consumed by `github-terraform-runner`.
- [AWS IAM policy](reference/aws-iam-policy.md) — statement-by-statement breakdown of the OIDC role policy that grants the runner access to S3 (state + private repo definitions).

## How to

- [Set up the GitHub PAT](how-to/setup-github-pat.md) — create, scope, and install the fine-grained PAT used by the runner. Includes the rotation procedure.
- [Apply the AWS IAM policy](how-to/apply-aws-iam-policy.md) — attach the policy from the reference doc to the OIDC role used by CI.

## Explanation

- [Runner credentials: design and gotchas](explanation/runner-credentials.md) — why this combination of credentials, the GET/PUT permission asymmetry on environments, the S3 `ListBucket` `max-keys` gotcha, and when to revisit GitHub App auth.

## Architecture decisions

ADRs are governed by [ADR-0001](https://github.com/nwarila-platform/.github/blob/main/docs/decision-records/0001-use-architecture-decision-records.md) and live at `.github/docs/decision-records/` per the org baseline, not under this `docs/` tree.

## Adding a document

1. Decide which quadrant the document belongs to. The four-quadrant test is in ADR-0002 §"Decision Outcome."
2. Create the file under the matching subdirectory.
3. Add a one-line entry in the corresponding section above.
4. If the document is a composite (runbook, troubleshooting guide), label its sections with `## Reference`, `## How to ...`, `## Why ...` per ADR-0002 §"Decision Outcome."
