# Operate the fleet watchdog

The watchdog detects pull requests deadlocked by a required status check that
never reports. This page covers running it, responding to what it finds, and the
things it deliberately does not cover.

## The failure it exists to catch

On 2026-07-20 a blocked action caused `org-adr-sync.yaml` to end in
`startup_failure` on `talos-cluster`. The required check `org-adr / verify`
therefore never posted. Three open pull requests became unmergeable **with no
failing check to point at** — the merge box showed a check waiting for a result
that would never arrive. Nothing detected it. A human noticed roughly nine hours
later.

This class of outage is invisible to ordinary CI monitoring, which watches for
checks that *fail*. Here nothing failed; something was absent.

## What it checks

**D2 — missing required context (the symptom).** For every open pull request, the
set of contexts required on that PR's base branch minus the set GitHub actually
holds a result for. Cause-agnostic by construction: it catches a blocked action,
a deleted workflow, a renamed job, or a path filter that never matches, without
needing to know which happened.

**D1 — `startup_failure` sweep (the cause).** Any workflow run in the last 24
hours that died before a job started. Threshold is one. Cheaper and earlier than
D2, but it enumerates a single known cause.

The layering is deliberate: D1 may rot as GitHub adds new pre-run failure modes,
and D2 cannot, because absence is absence regardless of cause. Keep both.

## Severity

| Severity | Meaning | Example |
|---|---|---|
| `page` | a PR is deadlocked right now | required context absent on a ready, non-draft PR |
| `warn` | real but not currently blocking a merge | same finding on a draft, or on a PR that also has conflicts |
| `notice` | pipeline rot, no PR impact | `startup_failure` on a scheduled or push-triggered run |

`notice` exists because `talos-cluster` alone carries roughly 695 lifetime
`startup_failure` runs, nearly all from scheduled workflows. Paging on those
would make the watchdog wallpaper within a week, and an ignored watchdog is
functionally identical to no watchdog.

## Exit codes

| Code | Meaning | Dead-man ping |
|---:|---|---|
| 0 | complete scan, nothing found | ping success |
| 1 | complete scan, findings exist | ping `/fail` |
| 2 | **scan integrity failure** | **ping nothing** |

Exit 2 means the scan did not complete and therefore proves nothing. It must not
reset the external timer — letting the grace period lapse is the correct signal
for "cannot tell", and is different in kind from "all clear".

Operational failure outranks findings. If findings exist but the scan was also
incomplete, the run exits 2 and prints the findings anyway.

## Responding to a finding

1. **Read the `cause` field first.** `workflow died before any job ran
   (startup_failure)` usually means an action is blocked by the repo's
   `allowed_actions` allow-list; the linked run shows which.
2. **Confirm in the merge box.** The PR should show a required check that never
   reports, not one that failed.
3. **Fix the producer, not the requirement.** Removing the required check to
   unblock a merge disables the gate for every future PR. Prefer restoring the
   producer; use the admin bypass actor if a merge is genuinely urgent.
4. **If the required context is permanently unsatisfiable** — the producing
   workflow was deleted or renamed — fix the ruleset in the runner YAML, not by
   hand in the UI, or Terraform will revert it.

## Responding to `WATCHDOG ERROR` (exit 2)

The scan is not telling you the fleet is healthy; it is telling you it could not
look. Common causes, in the order worth checking:

- **`FLEET_WATCHDOG_TOKEN` expired.** Fine-grained PATs expire (max 366 days).
- **Identity or permission drift.** The private canary or the legacy-protection
  probe failed. See "Why the token is pinned" below.
- **An unrecognized enforced rule type.** A repo now enforces a rule the detector
  does not model — most likely a merge queue, which relocates required checks
  onto a queue branch and invalidates D2's model. Extend the watchdog before
  enabling merge queues anywhere in the fleet.
- **A repo returned 404 after enumeration listed it.** Treated as fatal on
  purpose: enumeration already proved visibility, so a later 404 means something
  changed underneath the scan.

## Why the token is pinned

The tool refuses to run without an explicit `GH_TOKEN` and will not fall back to
an ambient CLI credential. The reason is specific rather than theoretical: `gh`
stores its active account in a shared, mutable config file, so a concurrent
process running `gh auth switch` re-points the identity of every running `gh`
process, mid-scan.

What makes that lethal rather than annoying is its shape. Under the reduced
privilege, public repositories keep answering normally while private ones return
404 — so the scan *completes*, exits 0, and reports rows that are quietly wrong.
This is not hypothetical: it is the mechanism behind the 2026-07-20 incident,
where a scan run under a drifted identity returned empty and the empty result was
read as "no references".

The startup capability probe exists for the same reason. A nonzero repository
count is not evidence of coverage — a token scoped to a subset returns a
plausible fleet and a convincing partial green. So the probe additionally
requires that a known **private** repo is readable, and that the
legacy-protection endpoint returns either data or specifically
`Branch not protected`; GitHub masks a 403 there as a bare `Not Found`, which
would otherwise read as "no protection configured" forever.

## Alert deduplication

There is deliberately no per-finding state store in v1. The dead-man monitor
provides deduplication for free: it notifies on state *transitions*, so a
persisting finding pings `/fail` every cycle without re-notifying, and recovery
produces exactly one "up" notification.

The limitation is granularity — the external channel is per-check, not
per-finding, so a *second* distinct finding appearing while a first is unresolved
does not generate its own notification. The job summary always lists every
current finding, so nothing is hidden; it is the paging that is coarse. Per-finding
issue state is the first item on the deferred list if that granularity is needed.

## Known gaps

These are gaps, not bugs. Each is a case where the watchdog will not tell you
something you might assume it would.

- **A required context that reports but never finishes.** D2 detects absence, not
  a check parked in `queued` or `in_progress` forever. That deadlocks a PR just
  as thoroughly.
- **Repos with required contexts and no open PRs.** D2 has nothing to inspect
  until a PR opens. `windows-certificate-store-exporter` is the live example: 4
  required contexts, typically zero open PRs. Renovate acts as an accidental
  canary here, usually opening a PR within a week.
- **Merge queues.** Not modelled at all; encountering one is a deliberate exit 2.
- **Rulesets switched to `evaluate` or `disabled`.** The requirement disappears,
  so D2 correctly goes quiet — while the fleet has silently lost a gate. That is
  configuration drift, owned by Terraform, not by this tool.
- **Personal-account repos.** Enumeration is organization-scoped, so
  `NWarila/drift-gate` is out of scope even though its breakage caused the
  incident. Such breakage surfaces downstream as consumer `startup_failure`s,
  which D1 and D2 do catch.

## Running it manually

```bash
GH_TOKEN=<fine-grained read-only org PAT> python3 tools/fleet_watchdog.py
```

Add `--config` to point at an alternative configuration. Exit codes are as above,
so it composes with `&&` in a shell without special handling.

Run the tests with `make watchdog-test`.
