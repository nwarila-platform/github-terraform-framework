#!/usr/bin/env python3
"""Detect pull requests deadlocked by a required status check that never reports.

On 2026-07-20 a blocked action made `org-adr-sync.yaml` end in `startup_failure`.
The required check `org-adr / verify` therefore never posted, and every open pull
request on `talos-cluster` became unmergeable **with no failing check to point at**.
Nothing detected it; a human noticed roughly nine hours later.

Two detectors, deliberately layered so that the cheap one may rot and the
authoritative one cannot:

D1 (cause)    any workflow run ending in `startup_failure`. Threshold 1. Cheap and
              early, but enumerates only one known cause.
D2 (symptom)  a context required on a pull request's base branch for which GitHub
              holds no result on any candidate commit. Cause-agnostic: it catches a
              blocked action, a deleted workflow, a renamed job, or a path filter
              that never matches, without knowing which happened.

The failure this tool must never exhibit is its own: a watchdog that reports
all-clear while broken is worse than no watchdog, because it converts an outage
into a silence that looks like health. Every ambiguous read is therefore an error,
never an empty result -- see `ScanIntegrityError` and exit code 2.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "tools" / "fleet-watchdog-config.json"

API = "https://api.github.com"
ACCEPT = "application/vnd.github+json"
API_VERSION = "2022-11-28"

EXIT_CLEAN = 0
EXIT_FINDINGS = 1
EXIT_INTEGRITY = 2

# Rule types D2 understands. An enforced rule of any other type may impose
# requirements this tool cannot see, so encountering one is a coverage failure
# rather than something to skip. `merge_queue` in particular relocates required
# checks onto a queue branch, which would silently invalidate D2's whole model.
KNOWN_RULE_TYPES = {
    "required_status_checks",
    "creation",
    "update",
    "deletion",
    "non_fast_forward",
    "required_linear_history",
    "required_signatures",
    "pull_request",
    "required_deployments",
    "commit_message_pattern",
    "commit_author_email_pattern",
    "committer_email_pattern",
    "branch_name_pattern",
    "tag_name_pattern",
    "code_scanning",
}
UNSUPPORTED_RULE_TYPES = {"merge_queue", "workflows"}

# D1 severity. Runs triggered by pull-request events gate merges and page; the
# rest are pipeline rot and are reported without paging. This is not cosmetic:
# talos-cluster alone carries ~695 lifetime startup_failures, nearly all from
# scheduled runs, and a detector that pages on all of them is ignored within a week.
PAGING_EVENTS = {"pull_request", "pull_request_target", "dynamic"}


class ScanIntegrityError(RuntimeError):
    """The scan cannot be trusted. Never downgrade this to a finding."""


@dataclass
class Finding:
    kind: str  # "D1" | "D2"
    severity: str  # "page" | "notice" | "warn"
    repo: str
    summary: str
    detail: str
    fingerprint: str
    url: str = ""


@dataclass
class Scan:
    findings: list[Finding] = field(default_factory=list)
    unscanned: list[str] = field(default_factory=list)
    repos_seen: int = 0
    prs_seen: int = 0
    deferred: int = 0

    def fail(self, what: str, why: str) -> None:
        self.unscanned.append(f"{what}: {why}")


def fingerprint(*parts: str) -> str:
    return hashlib.sha256("|".join(parts).encode()).hexdigest()[:12]


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def parse_ts(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


class GitHub:
    """Minimal REST client.

    Deliberately not a `gh` subprocess wrapper. Two requirements make the raw API
    necessary: the token must be pinned per-process (see `require_token`), and
    404 responses must be told apart by body text, which `gh` does not surface.
    """

    def __init__(self, token: str) -> None:
        self._token = token
        self.calls = 0

    def _request(self, path: str) -> tuple[int, Any, dict[str, str]]:
        url = path if path.startswith("http") else f"{API}{path}"
        req = urllib.request.Request(url)
        req.add_header("Authorization", f"Bearer {self._token}")
        req.add_header("Accept", ACCEPT)
        req.add_header("X-GitHub-Api-Version", API_VERSION)
        req.add_header("User-Agent", "nwarila-platform-fleet-watchdog")
        self.calls += 1
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.status, json.loads(resp.read() or b"null"), dict(resp.headers)
        except urllib.error.HTTPError as exc:
            raw = exc.read()
            try:
                body = json.loads(raw or b"null")
            except json.JSONDecodeError:
                body = {"message": (raw or b"").decode(errors="replace")}
            return exc.code, body, dict(exc.headers or {})

    def get(self, path: str) -> Any:
        """GET expecting success. Any non-2xx is an integrity failure."""
        status, body, _ = self._request(path)
        if status >= 400:
            message = (body or {}).get("message", "") if isinstance(body, dict) else ""
            raise ScanIntegrityError(f"GET {path} -> HTTP {status}: {message}")
        return body

    def get_allowing_404(self, path: str) -> tuple[Any, str]:
        """GET where absence is a legitimate answer.

        Returns (body, "") on 200 and (None, message) on 404. The message matters:
        GitHub masks a 403 as a bare "Not Found", so a caller that treats every 404
        as "nothing configured" will conclude a repo is unprotected when it has in
        fact lost read privilege. Callers must inspect the message.
        """
        status, body, _ = self._request(path)
        if status == 404:
            return None, (body or {}).get("message", "") if isinstance(body, dict) else ""
        if status >= 400:
            message = (body or {}).get("message", "") if isinstance(body, dict) else ""
            raise ScanIntegrityError(f"GET {path} -> HTTP {status}: {message}")
        return body, ""

    def paginate(self, path: str) -> Iterator[Any]:
        """Follow Link rel=next to exhaustion.

        Never infer completion from a short page: a filtered listing can return
        fewer than per_page and still carry a next link.
        """
        sep = "&" if "?" in path else "?"
        url = f"{path}{sep}per_page=100"
        pages = 0
        while url:
            status, body, headers = self._request(url)
            if status >= 400:
                message = (body or {}).get("message", "") if isinstance(body, dict) else ""
                raise ScanIntegrityError(f"GET {url} -> HTTP {status}: {message}")
            if isinstance(body, list):
                yield from body
            else:
                yield body
            pages += 1
            if pages > 100:
                raise ScanIntegrityError(f"pagination exceeded 100 pages for {path}")
            url = _next_link(headers.get("Link", ""))

    def login(self) -> str:
        return self.get("/user")["login"]


def _next_link(link_header: str) -> str:
    for part in link_header.split(","):
        section = part.split(";")
        if len(section) < 2:
            continue
        if 'rel="next"' in section[1].strip():
            return section[0].strip().strip("<>")
    return ""


def require_token() -> str:
    """Return GH_TOKEN, refusing to fall back to any ambient credential.

    `gh`'s active-account marker lives in a shared, mutable config file, so a
    concurrent process running `gh auth switch` re-points *this* process's identity
    mid-scan. Asserting identity once at startup does not close that window. What
    makes the drift lethal rather than merely annoying is its shape: while drifted
    to a lower-privilege account, public repositories keep answering while private
    ones return 404, so the scan completes, exits 0, and reports rows that are
    quietly wrong. Pinning the token per-process removes the window entirely.
    """
    token = os.environ.get("GH_TOKEN", "").strip()
    if not token:
        raise ScanIntegrityError(
            "GH_TOKEN is not set. This tool refuses ambient/CLI-managed credentials "
            "because a concurrent `gh auth switch` can change identity mid-scan."
        )
    return token


def capability_probe(gh: GitHub, cfg: dict) -> None:
    """Prove the credential can see everything the scan will claim to have checked.

    A nonzero repository count is not proof of coverage: a token scoped to a subset
    returns a plausible fleet and a convincing partial green.
    """
    expected = cfg["expected_login"]
    actual = gh.login()
    if actual != expected:
        raise ScanIntegrityError(f"authenticated as {actual!r}, expected {expected!r}")

    # A private repo proves the credential did not silently degrade to public-only
    # visibility -- the exact signature of mid-scan identity drift.
    canary = cfg.get("private_canary_repo")
    if canary:
        repo = gh.get(f"/repos/{canary}")
        if not repo.get("private"):
            raise ScanIntegrityError(
                f"private canary {canary} reports private=false; canary is misconfigured"
            )

    # Prove we can tell "no legacy protection" apart from "lost admin read".
    probe = cfg.get("legacy_protection_canary")
    if probe:
        repo_name, branch = probe["repo"], probe["branch"]
        _, message = gh.get_allowing_404(f"/repos/{repo_name}/branches/{branch}/protection")
        if message and "not protected" not in message.lower():
            raise ScanIntegrityError(
                f"legacy-protection probe on {repo_name}@{branch} returned {message!r}; "
                "a bare 'Not Found' is GitHub masking a 403, i.e. lost Administration:read"
            )


def enumerate_repos(gh: GitHub, cfg: dict) -> list[dict]:
    org = cfg["organization"]
    repos = [r for r in gh.paginate(f"/orgs/{org}/repos?type=all") if not r.get("archived")]
    if not repos:
        raise ScanIntegrityError(
            f"enumerated zero repositories in {org}. Never read empty as 'none' -- "
            "this is the signature of a drifted or under-scoped credential."
        )
    floor = cfg.get("minimum_repository_count", 1)
    if len(repos) < floor:
        raise ScanIntegrityError(f"enumerated {len(repos)} repos, below floor {floor}")

    names = {r["full_name"] for r in repos}
    missing = [s for s in cfg.get("sentinel_repositories", []) if s not in names]
    if missing:
        raise ScanIntegrityError(f"sentinel repositories absent from enumeration: {missing}")
    return repos


def required_contexts(gh: GitHub, full_name: str, branch: str) -> set[tuple[str, int | None]]:
    """Contexts GitHub will actually require for `branch`.

    Sourced from the effective-rules endpoint rather than by listing rulesets and
    re-implementing ref matching: it returns already-merged, active-enforcement-only
    rules, folds in organization-level rulesets, and needs only Metadata read.
    Legacy branch protection is unioned in -- unused across this fleet today, but one
    call per repo closes the hole if any repo ever migrates back.
    """
    required: set[tuple[str, int | None]] = set()

    encoded = urllib.parse.quote(branch, safe="")
    rules = gh.get(f"/repos/{full_name}/rules/branches/{encoded}")
    for rule in rules or []:
        rule_type = rule.get("type", "")
        if rule_type in UNSUPPORTED_RULE_TYPES:
            raise ScanIntegrityError(
                f"{full_name}@{branch} enforces rule type {rule_type!r}, which this "
                "detector does not model. Extend the watchdog before relying on it here."
            )
        if rule_type not in KNOWN_RULE_TYPES:
            raise ScanIntegrityError(
                f"{full_name}@{branch} enforces unrecognized rule type {rule_type!r}; "
                "failing closed rather than assuming it imposes no requirement."
            )
        if rule_type != "required_status_checks":
            continue
        params = rule.get("parameters") or {}
        for check in params.get("required_status_checks") or []:
            required.add((check["context"], check.get("integration_id")))

    legacy, message = gh.get_allowing_404(f"/repos/{full_name}/branches/{encoded}/protection")
    if legacy is None:
        if message and "not protected" not in message.lower():
            raise ScanIntegrityError(
                f"legacy protection on {full_name}@{branch} returned {message!r}; "
                "a bare 'Not Found' is a masked 403, not an unprotected branch"
            )
    else:
        checks = (legacy.get("required_status_checks") or {}).get("checks") or []
        for check in checks:
            required.add((check["context"], check.get("app_id")))

    return required


def reported_contexts(gh: GitHub, full_name: str, sha: str) -> set[tuple[str, int | None]]:
    """Every context GitHub holds a result for on `sha`, from both status mechanisms."""
    reported: set[tuple[str, int | None]] = set()

    for run in gh.paginate(f"/repos/{full_name}/commits/{sha}/check-runs?filter=latest"):
        if not isinstance(run, dict) or "name" not in run:
            continue
        app_id = (run.get("app") or {}).get("id")
        reported.add((run["name"], app_id))

    # The combined-status endpoint reports state "pending" with total_count 0 when
    # there are no statuses at all, so `state` says nothing about presence. Only the
    # statuses list is meaningful.
    combined, message = gh.get_allowing_404(f"/repos/{full_name}/commits/{sha}/status")
    if combined is None and message and "not found" not in message.lower():
        raise ScanIntegrityError(f"combined status for {full_name}@{sha}: {message}")
    for status in (combined or {}).get("statuses", []):
        reported.add((status["context"], (status.get("creator") or {}).get("id")))

    return reported


def satisfied(required: tuple[str, int | None], reported: set[tuple[str, int | None]]) -> bool:
    """Is a required context satisfied by anything GitHub actually holds?

    An unpinned requirement accepts any producer. A requirement pinned to an app
    accepts only that app: a same-named check from a different producer is exactly
    the impersonation the pin exists to prevent.
    """
    context, integration_id = required
    if integration_id is None:
        return any(name == context for name, _ in reported)
    return (context, integration_id) in reported


def classify_absence(gh: GitHub, full_name: str, sha: str) -> tuple[str, str]:
    """Best-effort cause for an absent required context. Returns (cause, url)."""
    try:
        suites = gh.get(f"/repos/{full_name}/commits/{sha}/check-suites")
    except ScanIntegrityError:
        return ("unknown (check-suites unreadable)", "")

    for suite in (suites or {}).get("check_suites", []):
        # Non-Actions apps park suites in `queued` with zero runs indefinitely;
        # reading those as evidence produces confident nonsense.
        if (suite.get("app") or {}).get("slug") != "github-actions":
            continue
        if suite.get("conclusion") == "startup_failure":
            url = ""
            try:
                runs = gh.get(f"/repos/{full_name}/actions/runs?head_sha={sha}")
                for run in runs.get("workflow_runs", []):
                    if run.get("conclusion") == "startup_failure":
                        url = run.get("html_url", "")
                        break
            except ScanIntegrityError:
                pass
            return ("workflow died before any job ran (startup_failure)", url)
        if suite.get("conclusion") == "action_required":
            return ("awaiting workflow approval", "")

    return ("no workflow run was created for this commit", "")


def scan_d1(gh: GitHub, repo: dict, since: datetime, scan: Scan) -> None:
    full_name = repo["full_name"]
    stamp = since.strftime("%Y-%m-%dT%H:%M:%SZ")
    path = f"/repos/{full_name}/actions/runs?status=startup_failure&created=>{urllib.parse.quote(stamp)}"
    for run in gh.paginate(path):
        if not isinstance(run, dict) or "id" not in run:
            continue
        event = run.get("event", "")
        paging = event in PAGING_EVENTS
        scan.findings.append(
            Finding(
                kind="D1",
                severity="page" if paging else "notice",
                repo=full_name,
                summary=f"{run.get('name', '?')} ended in startup_failure",
                detail=(
                    f"event={event} branch={run.get('head_branch', '?')} "
                    f"run={run['id']} at {run.get('created_at', '?')}"
                ),
                fingerprint=fingerprint("D1", full_name, str(run.get("path", "")), str(run["id"]))
                if paging
                else fingerprint(
                    "D1", full_name, str(run.get("path", "")), utcnow().strftime("%Y-%m-%d")
                ),
                url=run.get("html_url", ""),
            )
        )


def scan_d2(gh: GitHub, repo: dict, cfg: dict, scan: Scan) -> None:
    full_name = repo["full_name"]
    grace = timedelta(minutes=cfg.get("fresh_head_grace_minutes", 30))

    for pr in gh.paginate(f"/repos/{full_name}/pulls?state=open"):
        if not isinstance(pr, dict) or "number" not in pr:
            continue
        scan.prs_seen += 1
        number = pr["number"]
        base = pr["base"]["ref"]
        head_sha = pr["head"]["sha"]

        required = required_contexts(gh, full_name, base)
        if not required:
            continue

        # Candidate commits: GitHub evaluates pull-request workflows against a
        # synthetic test-merge commit, but results can land on either, and which one
        # counts is not fully specified. Taking the union is the conservative read --
        # it can only suppress a false alarm, never manufacture one.
        candidates = [head_sha]
        merge_sha = pr.get("merge_commit_sha")
        if merge_sha and merge_sha != head_sha:
            candidates.append(merge_sha)

        reported: set[tuple[str, int | None]] = set()
        for sha in candidates:
            reported |= reported_contexts(gh, full_name, sha)

        missing = sorted(
            (ctx for ctx in required if not satisfied(ctx, reported)), key=lambda c: c[0]
        )
        if not missing:
            continue

        # A brand-new head has not had time to report. Defer rather than alert,
        # but measure the head COMMIT's age, not the PR's updated_at -- a comment
        # bumps updated_at, so an active PR could otherwise defer past its own
        # grace indefinitely and never be reported.
        #
        # A ScanIntegrityError here is deliberately NOT caught: if the commit is
        # unreadable the credential has a problem, and that must surface as a
        # coverage failure rather than be smoothed over with a guessed timestamp.
        commit = gh.get(f"/repos/{full_name}/commits/{head_sha}")
        try:
            age = utcnow() - parse_ts(commit["commit"]["committer"]["date"])
        except (KeyError, TypeError, ValueError):
            # Malformed timestamp: fall back to the PR's own age. Erring toward
            # "old" reports rather than suppresses, which is the safe direction.
            age = utcnow() - parse_ts(pr["created_at"])
        if age < grace:
            scan.deferred += 1
            continue

        cause, url = classify_absence(gh, full_name, head_sha)
        names = ", ".join(ctx for ctx, _ in missing)
        draft = pr.get("draft", False)
        conflicted = pr.get("mergeable") is False

        if conflicted:
            severity = "warn"
            cause = f"{cause}; PR also has merge conflicts (primary blocker)"
        elif draft:
            severity = "warn"
        else:
            severity = "page"

        scan.findings.append(
            Finding(
                kind="D2",
                severity=severity,
                repo=full_name,
                summary=f"PR #{number}: required check(s) never reported: {names}",
                detail=f"base={base} head={head_sha[:12]} cause={cause}",
                fingerprint=fingerprint("D2", full_name, str(number), base, names),
                url=url or pr.get("html_url", ""),
            )
        )


def render(scan: Scan, cfg: dict) -> str:
    lines: list[str] = ["### Fleet workflow watchdog", ""]
    lines.append(
        f"Scanned **{scan.repos_seen}** repositories and **{scan.prs_seen}** open pull "
        f"requests in `{cfg['organization']}`."
    )
    if scan.deferred:
        lines.append(
            f"{scan.deferred} finding(s) deferred: head commit is inside the grace window."
        )
    lines.append("")

    if scan.unscanned:
        lines.append("#### Coverage failures")
        lines.append("")
        lines.append("The scan is incomplete. Absence of findings below proves nothing.")
        lines.append("")
        for item in scan.unscanned:
            lines.append(f"- {item}")
        lines.append("")

    order = {"page": 0, "warn": 1, "notice": 2}
    findings = sorted(scan.findings, key=lambda f: (order.get(f.severity, 3), f.repo))
    if not findings:
        lines.append("No deadlocked pull requests and no startup failures.")
        return "\n".join(lines)

    for severity, heading in (
        ("page", "Blocking"),
        ("warn", "Advisory"),
        ("notice", "Notices"),
    ):
        group = [f for f in findings if f.severity == severity]
        if not group:
            continue
        lines.append(f"#### {heading}")
        lines.append("")
        for finding in group:
            link = f" ([run]({finding.url}))" if finding.url else ""
            lines.append(f"- `{finding.repo}` — {finding.summary}{link}")
            lines.append(f"  - {finding.detail}")
            lines.append(f"  - fingerprint `{finding.fingerprint}`")
        lines.append("")

    return "\n".join(lines)


def load_config(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        cfg = json.load(handle)
    for key in ("organization", "expected_login"):
        if not cfg.get(key):
            raise ScanIntegrityError(f"config is missing required key {key!r}")
    return cfg


def run(cfg: dict) -> tuple[Scan, int]:
    gh = GitHub(require_token())
    scan = Scan()

    capability_probe(gh, cfg)
    repos = enumerate_repos(gh, cfg)
    since = utcnow() - timedelta(hours=cfg.get("d1_lookback_hours", 24))

    for repo in repos:
        full_name = repo["full_name"]
        scan.repos_seen += 1
        # A per-repo failure must not abort the sweep, but it must also never be
        # forgotten: the remainder is scanned and the run still exits 2, because a
        # partial scan may report findings and may never report "clean".
        try:
            scan_d1(gh, repo, since, scan)
        except ScanIntegrityError as exc:
            scan.fail(f"{full_name} D1", str(exc))
        try:
            scan_d2(gh, repo, cfg, scan)
        except ScanIntegrityError as exc:
            scan.fail(f"{full_name} D2", str(exc))

    # Re-assert identity after the sweep. The credential is pinned per-process so
    # drift should be impossible; this verifies that assumption rather than trusting it.
    final = gh.login()
    if final != cfg["expected_login"]:
        raise ScanIntegrityError(f"identity changed mid-scan to {final!r}; results discarded")

    if scan.unscanned:
        return scan, EXIT_INTEGRITY
    return scan, (EXIT_FINDINGS if scan.findings else EXIT_CLEAN)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument(
        "--summary",
        type=Path,
        default=Path(os.environ["GITHUB_STEP_SUMMARY"])
        if os.environ.get("GITHUB_STEP_SUMMARY")
        else None,
    )
    args = parser.parse_args(argv)

    started = time.monotonic()
    try:
        cfg = load_config(args.config)
        scan, code = run(cfg)
    except ScanIntegrityError as exc:
        print(f"WATCHDOG ERROR: {exc}", file=sys.stderr)
        if args.summary:
            args.summary.write_text(
                f"### Fleet workflow watchdog\n\n**WATCHDOG ERROR** — the scan did not "
                f"complete, so it proves nothing about fleet health.\n\n```\n{exc}\n```\n",
                encoding="utf-8",
            )
        return EXIT_INTEGRITY

    report = render(scan, cfg)
    print(report)
    print(f"\n({gh_calls_note(scan)}; {time.monotonic() - started:.1f}s)")
    if args.summary:
        args.summary.write_text(report + "\n", encoding="utf-8")
    if code == EXIT_INTEGRITY:
        print("WATCHDOG ERROR: scan incomplete; see coverage failures.", file=sys.stderr)
    return code


def gh_calls_note(scan: Scan) -> str:
    return f"{scan.repos_seen} repos, {scan.prs_seen} PRs, {len(scan.findings)} findings"


if __name__ == "__main__":
    sys.exit(main())
