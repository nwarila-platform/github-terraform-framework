# How to set up the GitHub PAT for the runner

**Type**: How-to (Diátaxis). For the permission matrix, see [`reference/github-pat-permissions.md`](../reference/github-pat-permissions.md). For rationale, see [`explanation/runner-credentials.md`](../explanation/runner-credentials.md).

This guide walks through creating, scoping, and installing the fine-grained Personal Access Token consumed by `github-terraform-runner` as the `FINE_GRAINED_PERSONAL_ACCESS_TOKEN` Actions secret. It also covers the rotation procedure.

## Prerequisites

- You are an **owner** of the `nwarila-platform` GitHub organization.
- You have **admin** access to the `nwarila-platform/github-terraform-runner` repository (to update the secret).
- You have a workstation that can browse `https://github.com/settings/personal-access-tokens` while signed in as the org owner.

## Procedure: create a new PAT

1. Open `https://github.com/settings/personal-access-tokens` and click **Generate new token**.
2. Fill in:
   - **Token name**: `nwarila-platform_github-terraform-runner` (or rotation-suffixed: `..._YYYY-MM-DD`).
   - **Resource owner**: `nwarila-platform`.
   - **Expiration**: **90 days**. Calendar a reminder to rotate before this date.
   - **Repository access**: **All repositories**. (See the explanation doc for the trade-off.)
3. Under **Repository permissions**, set exactly the following — every other permission stays at "No access":

   | Permission | Level |
   |---|---|
   | Metadata | Read (forced) |
   | Administration | Read and write |
   | Contents | Read and write |
   | Actions | Read and write |
   | Environments | Read and write |

   Add **Secrets: Read and write** and/or **Variables: Read and write** ONLY if a managed repo's YAML actually declares `environments[].secrets:` or `environments[].variables:`. Otherwise leave them at "No access" — declaring them on the PAT widens its blast radius without functional benefit.
4. Under **Organization permissions**, leave everything at "No access". The runner does not need org-level scopes.
5. Click **Generate token**. **Copy the token value immediately** — GitHub shows it once. If you miss it, regenerate from the PAT detail page.

## Procedure: install the PAT into the runner

1. Open `https://github.com/nwarila-platform/github-terraform-runner/settings/secrets/actions`.
2. If a secret named `FINE_GRAINED_PERSONAL_ACCESS_TOKEN` already exists, click its **Update** button. Otherwise click **New repository secret**.
3. Name: `FINE_GRAINED_PERSONAL_ACCESS_TOKEN`.
4. Value: paste the token copied in the previous procedure. No trailing whitespace.
5. Save.

## Verification

Trigger the terraform workflow and confirm a clean plan:

```bash
gh workflow run terraform.yml --repo nwarila-platform/github-terraform-runner
# wait for the run, then:
gh run list --repo nwarila-platform/github-terraform-runner --workflow terraform.yml --limit 1
gh run view <run-id> --repo nwarila-platform/github-terraform-runner --log | grep -E "Plan:|Error:"
```

Expected: `Plan: ... to add, ... to change, ... to destroy.` and no `403 Resource not accessible by personal access token` error.

If you see the 403 on `GET /repos/.../environments/{name}`, the most likely cause is that **Actions: Read and write** is missing from the PAT. See the troubleshooting section in [`explanation/runner-credentials.md`](../explanation/runner-credentials.md).

## Procedure: rotate the PAT

The PAT must be rotated before its expiration. Perform this every 90 days.

1. Open the existing PAT at `https://github.com/settings/personal-access-tokens`.
2. Click **Regenerate token**. Set the new expiration to 90 days. **Copy the new value immediately.**
3. Open the runner's secret at `https://github.com/nwarila-platform/github-terraform-runner/settings/secrets/actions`.
4. Click **Update** on `FINE_GRAINED_PERSONAL_ACCESS_TOKEN`. Paste the new value. Save.
5. Trigger the terraform workflow as in **Verification**. Confirm the plan succeeds with the new token.
6. Calendar the next rotation reminder for ~85 days from now (5-day buffer).

The old token value is invalidated by **Regenerate token** the moment the new one is created. There is no overlap window. If verification fails, revert by clicking **Regenerate token** again, then immediately update the secret. Do NOT leave the runner with a stale token between regeneration and secret-update — that interval is the only window where CI is broken.

## Procedure: revoke the PAT (incident response)

If you suspect the PAT value has leaked:

1. Open the PAT at `https://github.com/settings/personal-access-tokens`.
2. Click **Delete** (not Regenerate). The token is invalidated immediately.
3. Audit the GitHub org's audit log at `https://github.com/organizations/nwarila-platform/settings/audit-log` for any unexpected activity attributable to the token.
4. Create a fresh token by following **Procedure: create a new PAT**. Use a new name with the incident date suffix (e.g., `nwarila-platform_github-terraform-runner_post-incident-YYYY-MM-DD`).
5. Install the new token by following **Procedure: install the PAT into the runner**.
6. Document the incident in a post-mortem and link to the audit-log evidence.

## Related

- [`reference/github-pat-permissions.md`](../reference/github-pat-permissions.md) — the permission matrix this procedure implements.
- [`explanation/runner-credentials.md`](../explanation/runner-credentials.md) — rationale and known gotchas.
- [ADR-0002 (Adopt Diátaxis)](https://github.com/nwarila-platform/.github/blob/main/docs/decision-records/0002-adopt-diataxis-documentation-framework.md) — why this doc lives in `how-to/`.
