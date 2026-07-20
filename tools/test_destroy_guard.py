#!/usr/bin/env python3
"""Tests for the repository destroy guard.

A Terraform "delete" of `github_repository` is not necessarily a deletion.
`archive_on_destroy` defaults to true, so the provider's delete path archives the
repository instead — verified in the provider source, where the delete function
sets `archived = true` and calls Edit rather than Delete. The plan shows `delete`
either way, which is precisely why a guard reading the before-state is needed:
the plan alone cannot distinguish retirement from deletion.

The premature-archive fixture is the real plan shape from the-hero-wars-guys,
where a dotfile-blind glob dropped a definitions file and the plan proposed to
archive a live public org-profile repository.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "reusable-terraform-deploy.yaml"


def extract_guard() -> str:
    """Pull the guard's python out of the workflow so the shipped code is tested.

    Copying the logic into the test would let the two drift apart, and a guard
    that is not the one actually running is not evidence of anything.
    """
    text = WORKFLOW.read_text(encoding="utf-8")
    marker = "Guard repository destroys"
    assert marker in text, "guard step is missing from the workflow"
    body = text.split(marker, 1)[1]
    start = body.index("python3 - <<'PY'") + len("python3 - <<'PY'")
    end = body.index("\n          PY", start)
    return "\n".join(line[10:] for line in body[start:end].splitlines())


GUARD = extract_guard()


def run_guard(resource_changes: list[dict]) -> tuple[int, str]:
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "plan.json").write_text(json.dumps({"resource_changes": resource_changes}))
        (Path(tmp) / "guard.py").write_text(GUARD)
        proc = subprocess.run(
            [sys.executable, "guard.py"],
            cwd=tmp,
            env={"PATH": "/usr/bin:/bin"},
            capture_output=True,
            text=True,
        )
        return proc.returncode, proc.stdout + proc.stderr


def repo_delete(name: str, *, archived: bool, archive_on_destroy: bool = True) -> dict:
    return {
        "type": "github_repository",
        "index": name,
        "address": f'github_repository.repo["{name}"]',
        "change": {
            "actions": ["delete"],
            "before": {"archived": archived, "archive_on_destroy": archive_on_destroy},
        },
    }


def dependent_delete(addr: str, rtype: str) -> dict:
    return {"type": rtype, "address": addr, "change": {"actions": ["delete"], "before": {}}}


class GenuineDeletionTests(unittest.TestCase):
    def test_archive_on_destroy_false_is_refused(self):
        # The only path to an irreversible deletion.
        code, out = run_guard([repo_delete("doomed", archived=True, archive_on_destroy=False)])
        self.assertEqual(code, 1)
        self.assertIn("REFUSING TO DELETE REPOSITORIES", out)
        self.assertIn("archive_on_destroy = false", out)

    def test_refused_even_when_repository_is_already_archived(self):
        code, _ = run_guard([repo_delete("doomed", archived=True, archive_on_destroy=False)])
        self.assertEqual(code, 1)


class PrematureArchiveTests(unittest.TestCase):
    def test_the_real_incident_plan_is_blocked(self):
        # the-hero-wars-guys: .github was archived=false and live.
        changes = [
            repo_delete(".github", archived=False),
            dependent_delete('github_branch_default.default[".github"]', "github_branch_default"),
            dependent_delete('github_repository_file.codeowners[".github"]', "github_repository_file"),
        ] + [
            dependent_delete(f'github_repository_ruleset.branch[".github-rules-{i}"]',
                             "github_repository_ruleset")
            for i in range(3)
        ]
        code, out = run_guard(changes)
        self.assertEqual(code, 1)
        self.assertIn("NOT ARCHIVED FIRST", out)
        self.assertIn(".github", out)

    def test_error_points_at_the_likely_cause(self):
        code, out = run_guard([repo_delete("live-repo", archived=False)])
        self.assertEqual(code, 1)
        self.assertIn("no longer", out)
        self.assertIn("assembly step", out)

    def test_there_is_no_override_environment_variable(self):
        import os

        for candidate in ("ALLOW_DESTROY", "FORCE", "ALLOW_ARCHIVE"):
            os.environ[candidate] = "1"
        try:
            code, _ = run_guard([repo_delete("live-repo", archived=False)])
        finally:
            for candidate in ("ALLOW_DESTROY", "FORCE", "ALLOW_ARCHIVE"):
                os.environ.pop(candidate, None)
        self.assertEqual(code, 1)


class DeliberateRetirementTests(unittest.TestCase):
    def test_already_archived_repository_may_leave_management(self):
        # Second step of a deliberate retirement: the provider no-ops and state
        # forgets it. Blocking this would make retirement impossible.
        code, out = run_guard([repo_delete("retired", archived=True)])
        self.assertEqual(code, 0)
        self.assertIn("already archived", out)

    def test_mixed_plan_blocks_only_the_premature_one(self):
        code, out = run_guard(
            [repo_delete("retired", archived=True), repo_delete("live-repo", archived=False)]
        )
        self.assertEqual(code, 1)
        self.assertIn("live-repo", out)


class OtherResourceTests(unittest.TestCase):
    def test_dependent_resource_destroys_are_reported_not_blocked(self):
        # Rulesets and environments churn on ordinary edits.
        code, out = run_guard(
            [dependent_delete('github_repository_ruleset.branch["x-rules-0"]',
                              "github_repository_ruleset")]
        )
        self.assertEqual(code, 0)
        self.assertIn("non-repository resource(s) will be destroyed", out)

    def test_clean_plan_passes(self):
        code, out = run_guard([])
        self.assertEqual(code, 0)
        self.assertIn("No repository destroys", out)


class EdgeCaseTests(unittest.TestCase):
    def test_replace_counts_as_a_destroy(self):
        change = repo_delete("recreated", archived=False)
        change["change"]["actions"] = ["delete", "create"]
        code, _ = run_guard([change])
        self.assertEqual(code, 1)

    def test_missing_archive_on_destroy_is_treated_as_the_provider_default(self):
        # Absent from before-state means the provider default (true) applies;
        # assuming deletion here would block ordinary retirements.
        change = {
            "type": "github_repository",
            "index": "r",
            "address": 'github_repository.repo["r"]',
            "change": {"actions": ["delete"], "before": {"archived": True}},
        }
        code, _ = run_guard([change])
        self.assertEqual(code, 0)

    def test_null_before_state_is_not_treated_as_permission(self):
        change = {
            "type": "github_repository",
            "index": "r",
            "address": 'github_repository.repo["r"]',
            "change": {"actions": ["delete"], "before": None},
        }
        code, _ = run_guard([change])
        self.assertEqual(code, 1)  # unknown archived state -> premature


if __name__ == "__main__":
    unittest.main(verbosity=2)
