# Release Gates

PRs to `main` must pass:

- `Terraform Framework Tests` (Terraform fmt/init/validate/test with
  PR-visible summaries)
- `Drift Gate` on pull requests (org baseline plus template baseline)
- `Security`, which fans out into local framework-template reusable
  workflows for IaC scanning, CodeQL, and OpenSSF Scorecard

External workflow and action references must be SHA-pinned.
