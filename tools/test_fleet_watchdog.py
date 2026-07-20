#!/usr/bin/env python3
"""Tests for the fleet watchdog.

These target the traps that make a watchdog silently wrong rather than loudly
broken, because a detector that fails loudly is merely unavailable while one
that reports all-clear while blind actively conceals the outage it exists to
find. Every test below encodes a specific way that could happen.

Fixtures are recorded from the 2026-07-20 talos-cluster incident, so a
regression here means the tool would no longer catch the outage it was built for.
"""

from __future__ import annotations

import json
import unittest
from datetime import timedelta
from pathlib import Path
from unittest import mock

import fleet_watchdog as fw


class FakeGitHub:
    """Routes paths to canned responses. Unknown paths raise, so a test can never
    accidentally pass by exercising an unstubbed call."""

    def __init__(self, routes: dict, allow_404: dict | None = None) -> None:
        self.routes = routes
        self.allow_404 = allow_404 or {}
        self.seen: list[str] = []

    def _match(self, path: str, table: dict):
        self.seen.append(path)
        # Longest prefix wins. First-match would route
        # `/commits/{sha}/check-suites` to the `/commits/{sha}` stub purely
        # because of dict ordering, silently feeding a test the wrong response.
        best = max((k for k in table if path.startswith(k)), key=len, default=None)
        if best is None:
            raise AssertionError(f"unstubbed path: {path}")
        return table[best]

    def get(self, path):
        value = self._match(path, self.routes)
        if isinstance(value, Exception):
            raise value
        return value

    def get_allowing_404(self, path):
        best = max((k for k in self.allow_404 if path.startswith(k)), key=len, default=None)
        if best is not None:
            self.seen.append(path)
            return self.allow_404[best]
        return self._match(path, self.routes), ""

    def paginate(self, path):
        value = self._match(path, self.routes)
        if isinstance(value, Exception):
            raise value
        yield from value

    def login(self):
        return self.routes.get("/user", {}).get("login", "NWarila")


class RequireTokenTests(unittest.TestCase):
    def test_absent_token_is_an_integrity_error_not_a_fallback(self):
        # The tool must never quietly fall back to an ambient credential: a
        # shared CLI account marker can be re-pointed by another process mid-scan.
        with mock.patch.dict("os.environ", {}, clear=True):
            with self.assertRaises(fw.ScanIntegrityError):
                fw.require_token()

    def test_blank_token_is_rejected(self):
        with mock.patch.dict("os.environ", {"GH_TOKEN": "   "}, clear=True):
            with self.assertRaises(fw.ScanIntegrityError):
                fw.require_token()


class CapabilityProbeTests(unittest.TestCase):
    cfg = {
        "expected_login": "NWarila",
        "private_canary_repo": "org/private",
        "legacy_protection_canary": {"repo": "org/repo", "branch": "main"},
    }

    def test_wrong_identity_aborts(self):
        gh = FakeGitHub({"/user": {"login": "SomeoneElse"}})
        with self.assertRaises(fw.ScanIntegrityError):
            fw.capability_probe(gh, self.cfg)

    def test_private_canary_reading_as_public_aborts(self):
        # Degradation to public-only visibility is the drift signature: public
        # repos keep answering, private ones vanish, and the scan looks fine.
        gh = FakeGitHub(
            {"/user": {"login": "NWarila"}, "/repos/org/private": {"private": False}}
        )
        with self.assertRaises(fw.ScanIntegrityError):
            fw.capability_probe(gh, self.cfg)

    def test_masked_403_on_legacy_protection_aborts(self):
        # GitHub returns a bare "Not Found" when the token lacks permission.
        # Reading that as "no legacy protection" would make the union silently
        # empty forever.
        gh = FakeGitHub(
            {"/user": {"login": "NWarila"}, "/repos/org/private": {"private": True}},
            allow_404={"/repos/org/repo/branches/main/protection": (None, "Not Found")},
        )
        with self.assertRaises(fw.ScanIntegrityError):
            fw.capability_probe(gh, self.cfg)

    def test_genuinely_unprotected_branch_is_accepted(self):
        gh = FakeGitHub(
            {"/user": {"login": "NWarila"}, "/repos/org/private": {"private": True}},
            allow_404={
                "/repos/org/repo/branches/main/protection": (None, "Branch not protected")
            },
        )
        fw.capability_probe(gh, self.cfg)  # must not raise


class EnumerationTests(unittest.TestCase):
    cfg = {"organization": "org", "minimum_repository_count": 2, "sentinel_repositories": []}

    def test_zero_repos_aborts(self):
        gh = FakeGitHub({"/orgs/org/repos": []})
        with self.assertRaises(fw.ScanIntegrityError):
            fw.enumerate_repos(gh, self.cfg)

    def test_below_floor_aborts(self):
        gh = FakeGitHub({"/orgs/org/repos": [{"full_name": "org/a", "archived": False}]})
        with self.assertRaises(fw.ScanIntegrityError):
            fw.enumerate_repos(gh, self.cfg)

    def test_missing_sentinel_aborts(self):
        cfg = dict(self.cfg, sentinel_repositories=["org/must-exist"])
        gh = FakeGitHub(
            {
                "/orgs/org/repos": [
                    {"full_name": "org/a", "archived": False},
                    {"full_name": "org/b", "archived": False},
                ]
            }
        )
        with self.assertRaises(fw.ScanIntegrityError):
            fw.enumerate_repos(gh, cfg)

    def test_archived_repos_are_excluded_but_do_not_count_toward_floor(self):
        gh = FakeGitHub(
            {
                "/orgs/org/repos": [
                    {"full_name": "org/a", "archived": False},
                    {"full_name": "org/b", "archived": False},
                    {"full_name": "org/old", "archived": True},
                ]
            }
        )
        repos = fw.enumerate_repos(gh, self.cfg)
        self.assertEqual([r["full_name"] for r in repos], ["org/a", "org/b"])


class RequiredContextTests(unittest.TestCase):
    def _gh(self, rules, legacy=(None, "Branch not protected")):
        return FakeGitHub(
            {"/repos/org/r/rules/branches/main": rules},
            allow_404={"/repos/org/r/branches/main/protection": legacy},
        )

    def test_extracts_contexts_and_integration_ids(self):
        gh = self._gh(
            [
                {
                    "type": "required_status_checks",
                    "parameters": {
                        "required_status_checks": [
                            {"context": "org-adr / verify", "integration_id": 15368},
                            {"context": "Lint"},
                        ]
                    },
                }
            ]
        )
        self.assertEqual(
            fw.required_contexts(gh, "org/r", "main"),
            {("org-adr / verify", 15368), ("Lint", None)},
        )

    def test_merge_queue_rule_fails_closed(self):
        # A merge queue relocates required checks onto a queue branch, which
        # invalidates this detector's model entirely. Guessing would be worse
        # than refusing.
        gh = self._gh([{"type": "merge_queue", "parameters": {}}])
        with self.assertRaises(fw.ScanIntegrityError):
            fw.required_contexts(gh, "org/r", "main")

    def test_required_workflows_rule_fails_closed(self):
        gh = self._gh([{"type": "workflows", "parameters": {}}])
        with self.assertRaises(fw.ScanIntegrityError):
            fw.required_contexts(gh, "org/r", "main")

    def test_unrecognized_future_rule_type_fails_closed(self):
        gh = self._gh([{"type": "some_rule_github_adds_in_2027", "parameters": {}}])
        with self.assertRaises(fw.ScanIntegrityError):
            fw.required_contexts(gh, "org/r", "main")

    def test_legacy_protection_is_unioned_in(self):
        gh = self._gh(
            [],
            legacy=(
                {"required_status_checks": {"checks": [{"context": "legacy-ci", "app_id": 42}]}},
                "",
            ),
        )
        self.assertEqual(fw.required_contexts(gh, "org/r", "main"), {("legacy-ci", 42)})

    def test_masked_403_on_legacy_protection_aborts(self):
        gh = self._gh([], legacy=(None, "Not Found"))
        with self.assertRaises(fw.ScanIntegrityError):
            fw.required_contexts(gh, "org/r", "main")

    def test_branch_name_is_url_encoded(self):
        gh = self._gh([])
        gh.routes = {"/repos/org/r/rules/branches/feature%2Ffoo": []}
        gh.allow_404 = {"/repos/org/r/branches/feature%2Ffoo/protection": (None, "Branch not protected")}
        fw.required_contexts(gh, "org/r", "feature/foo")
        self.assertTrue(any("feature%2Ffoo" in p for p in gh.seen))


class ReportedContextTests(unittest.TestCase):
    def test_combined_status_pending_with_no_statuses_yields_nothing(self):
        # The combined-status endpoint reports state "pending" with total_count 0
        # when there are no statuses at all. Branching on `state` would invent a
        # result that does not exist.
        gh = FakeGitHub(
            {
                "/repos/org/r/commits/abc/check-runs": [],
                "/repos/org/r/commits/abc/status": {"state": "pending", "total_count": 0,
                                                    "statuses": []},
            }
        )
        self.assertEqual(fw.reported_contexts(gh, "org/r", "abc"), set())

    def test_check_runs_and_statuses_are_unioned(self):
        gh = FakeGitHub(
            {
                "/repos/org/r/commits/abc/check-runs": [
                    {"name": "Lint", "app": {"id": 15368}}
                ],
                "/repos/org/r/commits/abc/status": {
                    "state": "success",
                    "statuses": [{"context": "legacy-ci", "creator": {"id": 99}}],
                },
            }
        )
        self.assertEqual(
            fw.reported_contexts(gh, "org/r", "abc"),
            {("Lint", 15368), ("legacy-ci", 99)},
        )


class SatisfactionTests(unittest.TestCase):
    def test_unpinned_requirement_accepts_any_producer(self):
        self.assertTrue(fw.satisfied(("Lint", None), {("Lint", 999)}))

    def test_pinned_requirement_rejects_a_different_producer(self):
        # Accepting a same-named check from another app defeats the entire point
        # of pinning the requirement to an app.
        self.assertFalse(fw.satisfied(("Lint", 15368), {("Lint", 999)}))

    def test_pinned_requirement_accepts_the_pinned_producer(self):
        self.assertTrue(fw.satisfied(("Lint", 15368), {("Lint", 15368)}))

    def test_absent_context_is_never_satisfied(self):
        self.assertFalse(fw.satisfied(("org-adr / verify", None), {("Lint", 1)}))


class D2Tests(unittest.TestCase):
    """The incident itself, replayed."""

    def _incident_gh(self, *, head_age_minutes=120, extra=None, statuses=None):
        old = (fw.utcnow() - timedelta(minutes=head_age_minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
        routes = {
            "/repos/org/talos/pulls": [
                {
                    "number": 354,
                    "base": {"ref": "main"},
                    "head": {"sha": "dead", "repo": {"full_name": "org/talos"}},
                    "merge_commit_sha": "merge1",
                    "created_at": old,
                    "draft": False,
                    "mergeable": True,
                    "html_url": "https://example.invalid/pr/354",
                }
            ],
            "/repos/org/talos/rules/branches/main": [
                {
                    "type": "required_status_checks",
                    "parameters": {
                        "required_status_checks": [
                            {"context": "org-adr / verify"},
                            {"context": "Lint"},
                        ]
                    },
                }
            ],
            "/repos/org/talos/commits/dead/check-runs": [{"name": "Lint", "app": {"id": 1}}],
            "/repos/org/talos/commits/merge1/check-runs": [],
            "/repos/org/talos/commits/dead/status": {"state": "pending", "statuses": statuses or []},
            "/repos/org/talos/commits/merge1/status": {"state": "pending", "statuses": []},
            "/repos/org/talos/commits/dead": {"commit": {"committer": {"date": old}}},
            "/repos/org/talos/commits/dead/check-suites": {
                "check_suites": [
                    {"app": {"slug": "renovate"}, "conclusion": None},
                    {
                        "app": {"slug": "github-actions"},
                        "conclusion": "startup_failure",
                        "latest_check_runs_count": 0,
                    },
                ]
            },
            "/repos/org/talos/actions/runs?head_sha=dead": {
                "workflow_runs": [
                    {"conclusion": "startup_failure", "html_url": "https://example.invalid/run/1"}
                ]
            },
        }
        routes.update(extra or {})
        return FakeGitHub(routes, allow_404={
            "/repos/org/talos/branches/main/protection": (None, "Branch not protected")
        })

    cfg = {"fresh_head_grace_minutes": 30}

    def test_detects_the_absent_required_context(self):
        scan = fw.Scan()
        fw.scan_d2(self._incident_gh(), {"full_name": "org/talos"}, self.cfg, scan)
        self.assertEqual(len(scan.findings), 1)
        finding = scan.findings[0]
        self.assertIn("org-adr / verify", finding.summary)
        self.assertNotIn("Lint", finding.summary)  # Lint reported; only the absent one
        self.assertEqual(finding.severity, "page")

    def test_attributes_the_startup_failure_as_the_cause(self):
        scan = fw.Scan()
        fw.scan_d2(self._incident_gh(), {"full_name": "org/talos"}, self.cfg, scan)
        self.assertIn("startup_failure", scan.findings[0].detail)
        self.assertEqual(scan.findings[0].url, "https://example.invalid/run/1")

    def test_fresh_head_is_deferred_not_alerted(self):
        scan = fw.Scan()
        fw.scan_d2(self._incident_gh(head_age_minutes=5), {"full_name": "org/talos"}, self.cfg, scan)
        self.assertEqual(scan.findings, [])
        self.assertEqual(scan.deferred, 1)

    def test_context_present_only_on_the_merge_commit_is_not_a_finding(self):
        # GitHub evaluates pull-request workflows against a synthetic test-merge
        # commit. Inspecting only the head SHA would call a healthy PR deadlocked.
        gh = self._incident_gh(
            extra={
                "/repos/org/talos/commits/merge1/check-runs": [
                    {"name": "org-adr / verify", "app": {"id": 1}}
                ]
            }
        )
        scan = fw.Scan()
        fw.scan_d2(gh, {"full_name": "org/talos"}, self.cfg, scan)
        self.assertEqual(scan.findings, [])

    def test_context_satisfied_by_a_legacy_commit_status_is_not_a_finding(self):
        gh = self._incident_gh(statuses=[{"context": "org-adr / verify", "creator": {"id": 7}}])
        scan = fw.Scan()
        fw.scan_d2(gh, {"full_name": "org/talos"}, self.cfg, scan)
        self.assertEqual(scan.findings, [])

    def test_draft_pr_warns_but_does_not_page(self):
        gh = self._incident_gh()
        gh.routes["/repos/org/talos/pulls"][0]["draft"] = True
        scan = fw.Scan()
        fw.scan_d2(gh, {"full_name": "org/talos"}, self.cfg, scan)
        self.assertEqual(scan.findings[0].severity, "warn")

    def test_conflicted_pr_warns_and_names_the_primary_blocker(self):
        gh = self._incident_gh()
        gh.routes["/repos/org/talos/pulls"][0]["mergeable"] = False
        scan = fw.Scan()
        fw.scan_d2(gh, {"full_name": "org/talos"}, self.cfg, scan)
        self.assertEqual(scan.findings[0].severity, "warn")
        self.assertIn("conflict", scan.findings[0].detail)

    def test_fingerprint_is_stable_across_a_new_head_sha(self):
        # Including head_sha would re-page on every push during one uninterrupted
        # outage, which trains the operator to ignore the watchdog.
        first = self._incident_gh()
        scan_a = fw.Scan()
        fw.scan_d2(first, {"full_name": "org/talos"}, self.cfg, scan_a)

        second = self._incident_gh()
        second.routes["/repos/org/talos/pulls"][0]["head"]["sha"] = "beef"
        for suffix in ("/check-runs", "/status", "", "/check-suites"):
            second.routes[f"/repos/org/talos/commits/beef{suffix}"] = second.routes[
                f"/repos/org/talos/commits/dead{suffix}"
            ]
        second.routes["/repos/org/talos/actions/runs?head_sha=beef"] = second.routes[
            "/repos/org/talos/actions/runs?head_sha=dead"
        ]
        scan_b = fw.Scan()
        fw.scan_d2(second, {"full_name": "org/talos"}, self.cfg, scan_b)

        self.assertEqual(scan_a.findings[0].fingerprint, scan_b.findings[0].fingerprint)

    def test_repo_with_no_required_contexts_produces_nothing(self):
        gh = self._incident_gh(extra={"/repos/org/talos/rules/branches/main": []})
        scan = fw.Scan()
        fw.scan_d2(gh, {"full_name": "org/talos"}, self.cfg, scan)
        self.assertEqual(scan.findings, [])


class D1Tests(unittest.TestCase):
    def _run(self, event):
        return {
            "id": 999,
            "name": "Org ADR Sync",
            "event": event,
            "head_branch": "renovate/x",
            "path": ".github/workflows/org-adr-sync.yaml",
            "created_at": "2026-07-20T04:10:25Z",
            "html_url": "https://example.invalid/run/999",
        }

    def test_pull_request_startup_failure_pages(self):
        gh = FakeGitHub({"/repos/org/r/actions/runs": [self._run("pull_request")]})
        scan = fw.Scan()
        fw.scan_d1(gh, {"full_name": "org/r"}, fw.utcnow(), scan)
        self.assertEqual(scan.findings[0].severity, "page")

    def test_scheduled_startup_failure_is_only_a_notice(self):
        # talos-cluster alone carries ~695 lifetime startup_failures, nearly all
        # from scheduled runs. Paging on those makes the watchdog wallpaper.
        gh = FakeGitHub({"/repos/org/r/actions/runs": [self._run("schedule")]})
        scan = fw.Scan()
        fw.scan_d1(gh, {"full_name": "org/r"}, fw.utcnow(), scan)
        self.assertEqual(scan.findings[0].severity, "notice")

    def test_threshold_is_one(self):
        gh = FakeGitHub({"/repos/org/r/actions/runs": [self._run("pull_request")]})
        scan = fw.Scan()
        fw.scan_d1(gh, {"full_name": "org/r"}, fw.utcnow(), scan)
        self.assertEqual(len(scan.findings), 1)


class PaginationTests(unittest.TestCase):
    def test_next_link_is_extracted(self):
        header = '<https://api.github.com/x?page=2>; rel="next", <https://api.github.com/x?page=9>; rel="last"'
        self.assertEqual(fw._next_link(header), "https://api.github.com/x?page=2")

    def test_absent_next_link_terminates(self):
        self.assertEqual(fw._next_link('<https://api.github.com/x?page=1>; rel="prev"'), "")
        self.assertEqual(fw._next_link(""), "")


class RenderTests(unittest.TestCase):
    cfg = {"organization": "org"}

    def test_coverage_failures_are_stated_before_any_all_clear(self):
        # A partial scan may report findings; it may never report "clean".
        scan = fw.Scan(repos_seen=3)
        scan.fail("org/x D2", "HTTP 403")
        out = fw.render(scan, self.cfg)
        self.assertIn("Coverage failures", out)
        self.assertIn("proves nothing", out)

    def test_clean_scan_says_so(self):
        out = fw.render(fw.Scan(repos_seen=21, prs_seen=27), self.cfg)
        self.assertIn("No deadlocked pull requests", out)


class ConfigTests(unittest.TestCase):
    def test_shipped_config_is_valid_and_complete(self):
        cfg = fw.load_config(Path(__file__).resolve().parent / "fleet-watchdog-config.json")
        self.assertEqual(cfg["organization"], "nwarila-platform")
        self.assertTrue(cfg["private_canary_repo"])
        self.assertTrue(cfg["sentinel_repositories"])

    def test_missing_required_key_is_rejected(self):
        import tempfile

        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump({"organization": "org"}, handle)
            path = Path(handle.name)
        with self.assertRaises(fw.ScanIntegrityError):
            fw.load_config(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
