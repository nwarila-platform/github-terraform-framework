# Architecture Decision Records

This directory holds the Architecture Decision Records (ADRs) governing this repository, split into two scopes per [ADR-0001](org/0001-use-architecture-decision-records.md):

- [`org/`](org/) — byte-identical mirror of the org-baseline ADRs whose master copies live in [`nwarila-platform/.github`](https://github.com/nwarila-platform/.github/tree/main/docs/decision-records). These apply across the organization and travel with every adopting repo.
- `repo/` *(empty)* — repository-specific ADRs that apply only to this repo. Independent numbering namespace from the org mirror; would live at `repo/NNNN-short-kebab-title.md` if any existed.

The MADR 4.0-aligned format and lifecycle rules are the same across both scopes; see [ADR-0001 §"Decision Outcome"](org/0001-use-architecture-decision-records.md) for details.

## Index

### Org-mirrored

| #  | Title | Status | Date | Summary |
|----|-------|--------|------|---------|
| [org/0001](org/0001-use-architecture-decision-records.md) | Use Architecture Decision Records to Document Design Rationale | Accepted | 2026-04-22 | Adopt ADRs as the documentation format for architecturally significant decisions. |
| [org/0002](org/0002-adopt-diataxis-documentation-framework.md) | Adopt Diátaxis as the Documentation Framework | Accepted | 2026-04-24 | Adopt the Diátaxis four-quadrant framework for non-ADR documentation in adopting repositories. |
| [org/0003](org/0003-use-deny-all-gitignore-strategy.md) | Use a Deny-All `.gitignore` Strategy | Accepted | 2026-04-25 | Adopt deny-all `.gitignore` with explicit allowlist as the default tracking strategy for adopting repositories. |

### Repository-specific

None yet. The first repository-specific ADR will live at `repo/0001-short-kebab-title.md` and a row will be added here.

## Authoring rules

- **Org-baseline ADRs are mirrors only.** Do not edit files under `org/` in this repository directly. The master copies live in [`nwarila-platform/.github/docs/decision-records/`](https://github.com/nwarila-platform/.github/tree/main/docs/decision-records). Amendments are PR'd in the org repo and synced down here.
- **Repo-specific ADRs go under `repo/`.** Follow the [ADR-0001 §"Decision Outcome"](org/0001-use-architecture-decision-records.md) numbering and template rules. The `repo/` namespace is independent of `org/` (`org/0001` and `repo/0001` can coexist).
- **Updating this index** is the same PR as adding the new ADR.
