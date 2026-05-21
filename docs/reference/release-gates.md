# Release Gates

PRs to `main` must pass:

- `Terraform Framework Tests` (Terraform fmt/init/validate/test with
  PR-visible summaries)
- `Drift Gate` on pull requests (org baseline plus template baseline)
- `CodeQL Analysis`, `Security Scan`, and `Scorecard` via the portable
  reusable workflows in `NWarila/terraform-template-template`

Reusable workflow calls must be SHA-pinned.
