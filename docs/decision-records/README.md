# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) governing this repository, split into three scopes per [ADR-0001](org/0001-use-architecture-decision-records.md):

- [`org/`](org/) â€” byte-identical mirror of the org-baseline ADRs whose master copies live in [`nwarila-platform/.github`](https://github.com/nwarila-platform/.github/tree/main/docs/decision-records). These apply across the organization and travel with every adopting repo.
- [`template/`](template/) â€” inherited Terraform framework decisions that apply across derived framework repositories.
- `repo/` *(empty)* â€” repository-specific ADRs that apply only to this repo. Independent numbering namespace from the org mirror; would live at `repo/NNNN-short-kebab-title.md` if any existed.

The MADR 4.0-aligned format and lifecycle rules are the same across all scopes; see [ADR-0001 Â§"Decision Outcome"](org/0001-use-architecture-decision-records.md) for details.

## Index

### Org-mirrored

| #  | Title | Status | Date | Summary |
|----|-------|--------|------|---------|
| [org/0001](org/0001-use-architecture-decision-records.md) | Use Architecture Decision Records to Document Design Rationale | Accepted | 2026-04-22 | Adopt ADRs as the documentation format for architecturally significant decisions. |
| [org/0002](org/0002-adopt-diataxis-documentation-framework.md) | Adopt DiÃ¡taxis as the Documentation Framework | Accepted | 2026-04-24 | Adopt the DiÃ¡taxis four-quadrant framework for non-ADR documentation in adopting repositories. |
| [org/0003](org/0003-use-deny-all-gitignore-strategy.md) | Use a Deny-All `.gitignore` Strategy | Accepted | 2026-04-25 | Adopt deny-all `.gitignore` with explicit allowlist as the default tracking strategy for adopting repositories. |
| [org/0004](org/0004-use-renovate-for-dependency-updates.md) | Use Renovate for Dependency Updates with Per-Template Baselines | Accepted | 2026-06-02 | Standardize on Renovate for platform repos with explicit type-template preset paths that consuming repos extend. |
| [org/0005](org/0005-keep-github-control-planes-namespace-local.md) | Keep GitHub Control Planes Namespace-Local | Accepted | 2026-06-02 | Use the owning namespace control plane for governance, ADRs, repo hygiene, and reusable workflow callers. |

### Template-mirrored

| # | Title | Status | Date | Summary |
|----|-------|--------|------|---------|
| [template/0001](template/0001-pin-terraform-and-provider-versions-exactly.md) | Pin Terraform and Provider Versions Exactly | Accepted | 2026-05-06 | Pin the Terraform CLI and every provider to exact versions. |

### Repository-specific

None yet. The first repository-specific ADR will live at `repo/0001-short-kebab-title.md` and a row will be added here.

## Authoring rules

- **Org-baseline ADRs are mirrors only.** Do not edit files under `org/` in this repository directly. The master copies live in [`nwarila-platform/.github/docs/decision-records/`](https://github.com/nwarila-platform/.github/tree/main/docs/decision-records). Amendments are PR'd in the org repo and synced down here.
- **Repo-specific ADRs go under `repo/`.** Follow the [ADR-0001 Â§"Decision Outcome"](org/0001-use-architecture-decision-records.md) numbering and template rules. The `repo/` namespace is independent of `org/` (`org/0001` and `repo/0001` can coexist).
- **Updating this index** is the same PR as adding the new ADR.
