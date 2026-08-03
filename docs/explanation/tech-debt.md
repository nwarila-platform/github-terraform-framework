# Tech debt and accepted risk

Known weaknesses in what this framework controls, recorded so they are decisions
rather than surprises. Each entry states the risk, why it is currently accepted,
what would close it, and how it would be noticed if it were exploited.

An entry here is not a bug report. It is a position: someone weighed it and chose
to live with it for now.

---

## TD-1 — Fork pull requests and self-hosted runners

**Status:** accepted, deliberately. **Owner decision.**

Self-hosted runners are permitted on **all** repositories. This is an explicit
choice, not an oversight: the platform's ephemeral Talos-based runners are held to
be materially more secure than GitHub-hosted ones, and a great deal of work went
into making that true.

The risk it accepts is the standard one, and it is real. GitHub's own guidance is
not to use self-hosted runners with public repositories, because a fork pull
request can execute attacker-authored code on infrastructure you own. An ephemeral
runner bounds *persistence* — the machine is destroyed after the job — but it does
not bound what that code can reach **while running**: the runner's network
position, any credentials reachable from it, and whatever the cluster exposes to
it.

Mitigations relied on today:

- `pull_request` from a fork receives a read-only `GITHUB_TOKEN` and **no**
  repository secrets. Fork PRs cannot exfiltrate secrets through the token path.
- GitHub requires manual approval before workflows run on PRs from first-time
  contributors. On a solo-maintainer org this is close to an absolute gate in
  practice.
- Runners are ephemeral, so a compromise does not persist into the next job.

What is **not** mitigated:

- `pull_request_target` runs in the base repository's context **with** secrets. A
  single workflow using that trigger and checking out the PR head reverses every
  protection above. Nothing in this framework currently prevents one being added.
- Network reachability from the runner into the cluster during the job.

**What would close it:** either restrict self-hosted runners to private
repositories and non-fork events, or add a checker that fails when any workflow
combines `pull_request_target` with a checkout of the PR head. The latter is
cheap and preserves the current posture — it is the better first step.

**How it would be noticed:** it would not be, today. This is the weakest part of
the entry.

---

## TD-2 — `can_approve_pull_request_reviews` is enabled

**Status:** unreviewed. Surfaced 2026-07-20 while auditing fork posture.

`talos-cluster` and `github-terraform-framework` both report:

```json
{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": true}
```

GitHub's default is `false`. With it `true`, GitHub Actions can submit approving
reviews — so a workflow can approve a pull request.

It does not appear to be *directly* exploitable here, because the Pull Request
Gate ruleset also sets `require_code_owner_review: true` and
`require_last_push_approval: true`, and Actions is not a code owner. The concern
is that the review-count requirement is being satisfied by a mechanism nobody
chose, and the code-owner rule is the only thing standing behind it.

**What would close it:** set it to `false` and manage it in Terraform like every
other repository setting. It is not currently framework-managed at all, which is
its own small finding — an unmanaged setting drifts silently.

---

## TD-3 — Organization-level Actions policy is unverifiable

**Status:** blocked on a credential grant.

`GET /orgs/{org}/actions/permissions` and
`/orgs/{org}/actions/permissions/workflow` both return 403 with the current token:
they require `admin:org` (or the Actions-policy fine-grained permission).

So the org-wide answers to "are fork PR workflows gated?" and "which actions are
allowed org-wide?" cannot be read, only assumed. Per-repository policy is
verifiable and is verified; the layer above it is not.

**What would close it:** grant the token `admin:org` read, or a fine-grained token
with Actions policy read. Until then, any claim about org-wide Actions posture in
this repository is an assumption.

---

## TD-4 — A `plan_only` pull-request plan cannot prove "only what I intended"

**Status:** accepted; work around it.

Under `plan_only` the deploy workflow replaces the S3 backend with an ephemeral
local one and seeds it by importing repositories, rulesets and organization
settings — and nothing else. Every other resource therefore appears as `create` on
every pull request, currently 47 of them.

This is correct and deliberate: it keeps pull-request CI from touching canonical
state, guarded twice over (AWS credentials are also skipped). But it means a PR
plan is a **from-scratch** plan, not a differential one. A reviewer cannot use it
to confirm that a change alters only what was intended, because the intended
change is buried in structural creates that appear regardless.

This has already caused one false alarm: the 47 creates were read as evidence of a
damaged state file before the ephemeral-backend design was noticed.

**Work around it:** assert live changes with a `workflow_dispatch` run and
`apply: false`, which uses the S3 backend and produces a real differential plan.
The sanitized summary is emitted to stdout as well as the job summary, so that
plan can be asserted programmatically.

**What would close it:** label the PR summary explicitly as a from-scratch plan so
the structural creates are not mistaken for drift by the next reader.

---

## TD-5 — Composite actions are not policy-enforced

**Status:** accepted; upstream limitation.

The `allowed_actions` allow-list governs actions referenced by a workflow. It is
**not** applied to actions referenced from inside a composite action. A permitted
composite action can therefore pull in a reference the allow-list would reject.

Nothing in the framework can fix this; it is GitHub's enforcement boundary.

**What would close it:** upstream change, or a checker that resolves composite
actions transitively and audits their references against the same allow-list. The
pre-flight written for the `verified_allowed` change already does this recursion
manually and could be generalized.

---

## TD-6 — `verified_allowed` is unauditable when enabled

**Status:** mitigated 2026-07-20, not eliminated.

`allowed_actions_config.verified_allowed` permits any Marketplace action from a
GitHub-verified creator. That set is open-ended, changes without a commit, and —
decisively — **no supported API resolves whether a given action would qualify**.
While it is `true`, the effective allow-list is not statically provable and no
checker can audit it.

Mitigated by defaulting it to `false` (fail-closed) and setting it explicitly to
`false` on the only repository using `allowed_actions: selected`. It remains
available, so the hole reopens for any repository that sets it `true`.

**What would close it:** a validation rule rejecting `verified_allowed: true`
outright, if the ergonomic cost is acceptable.

---

## TD-7 — Generated Terraform reference drift is not gated here

**Status:** accepted for now; tracked for a dedicated follow-up.

This repository's CI runs neither `make ci` nor `make docs-diff`. Changes to
Terraform can therefore leave the generated reference stale while framework CI
remains green. The drift becomes visible only when a consumer runs the full
`make ci`, where `docs-diff` fails.

The gap is accepted temporarily because changing framework PR gating has its own
blast radius and is being handled separately from repairing the current drift.
Consumers still detect the mismatch, but only after it has escaped this
repository's checks.

**What would close it:** add a docs-only framework PR gate that installs
checksum-verified `terraform-docs` 0.23.0 and runs `make docs-diff`.

**How it would be noticed:** a downstream consumer's `make ci` fails at
`docs-diff`, or a maintainer runs `make docs-diff` locally.
