#!/usr/bin/env python3
"""Regression tests for the shipped detector-mode workflow.

The predicates and executable shell bodies are extracted from the reusable
workflow. Keeping copies of that logic here would allow the tests and the YAML
to drift independently.
"""

from __future__ import annotations

import itertools
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

import verify_provider_gaps as provider_gaps


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = Path(
    os.environ.get(
        "DETECTOR_WORKFLOW",
        ROOT / ".github" / "workflows" / "reusable-terraform-deploy.yaml",
    )
)
VERSIONS = ROOT / "terraform" / "versions.tf"
RESOURCES = ROOT / "terraform" / "resources.tf"
WORKFLOW_TEXT = WORKFLOW.read_text(encoding="utf-8")

TITLE = "Configuration drift or state-binding gap detected"
LABEL_DESCRIPTION = (
    "Actionable Terraform or provider-gap drift, declaration errors, "
    "or missing state bindings"
)
INDETERMINATE = "INDETERMINATE / state-binding-missing"
DRIFT = "DRIFT / live-mismatch"
INVENTORY_UNDECLARED = "INVENTORY / undeclared-live"
INVENTORY_UNVERIFIED = "INVENTORY / enumeration-unverified"
INVENTORY_OWNER = "test-owner"
NON_PUBLIC_SENTINEL = "owner-only-sensitive-sentinel-7f3"
TOKEN_SENTINEL = "token-sensitive-sentinel-7f3"
RAW_BODY_SENTINEL = "raw-metadata-body-sentinel-7f3"
RAW_PLAN_SENTINEL = "raw-plan-fragment-sentinel-7f3"
PROVIDER_POLICY = "all_external_contributors"
OTHER_PROVIDER_POLICY = "first_time_contributors"
PRIVATE_PROVIDER_SENTINEL = "private-provider-sentinel-7f2"


def step_block(name: str) -> str:
    """Return one shipped step, stopping at the next step."""
    match = re.search(
        rf"(?ms)^      - name: {re.escape(name)}\n.*?(?=^      - name: |\Z)",
        WORKFLOW_TEXT,
    )
    if match is None:
        raise AssertionError(f"workflow step is missing: {name}")
    return match.group(0)


def step_if(name: str) -> str:
    match = re.search(r"(?m)^        if: (.+)$", step_block(name))
    if match is None:
        raise AssertionError(f"workflow step has no predicate: {name}")
    return match.group(1)


def step_run(name: str) -> str:
    """Extract and de-indent the exact run block of a shipped step."""
    block = step_block(name)
    marker = "        run: |\n"
    if marker not in block:
        raise AssertionError(f"workflow step has no literal run block: {name}")
    raw = block.split(marker, 1)[1]
    lines = []
    for line in raw.splitlines():
        if line and not line.startswith("          "):
            break
        lines.append(line[10:] if line else "")
    return "\n".join(lines) + "\n"


def eval_predicate(expression: str, *, plan_only: bool, apply: bool, drift_issue: bool,
                   github_is_organization: bool = True) -> bool:
    """Evaluate the asserted Actions boolean subset used by detector gates."""
    if not expression.startswith("${{ ") or not expression.endswith(" }}"):
        raise AssertionError(f"not an Actions expression: {expression}")
    body = expression[4:-3]
    values = {
        "plan_only": plan_only,
        "apply": apply,
        "drift_issue": drift_issue,
        "github_is_organization": github_is_organization,
    }
    body = re.sub(
        r"inputs\.(plan_only|apply|drift_issue|github_is_organization)",
        lambda match: str(values[match.group(1)]),
        body,
    )
    body = body.replace("always()", "True")
    body = body.replace("&&", " and ").replace("||", " or ")
    body = re.sub(r"!\s*", " not ", body).strip()
    if re.search(r"[^A-Za-z()\s]", body):
        raise AssertionError(f"unsupported predicate token: {body}")
    return bool(eval(body, {"__builtins__": {}}, {"True": True, "False": False}))


def change(address: str, actions: list[str], resource_type: str = "github_repository",
           before: dict | None = None) -> dict:
    row = {
        "address": address,
        "mode": "managed",
        "type": resource_type,
        "name": "repo",
    }
    if resource_type == "github_repository":
        match = re.search(r'\["([A-Za-z0-9._-]+)"\]$', address)
        if match is None:
            raise AssertionError(f"repository fixture address has no valid key: {address}")
        name = match.group(1)
        values = {"name": name, "visibility": "public"}
        row["index"] = name
        prior = {**values, **(before or {})}
        row["change"] = {
            "actions": actions,
            "before": None if actions == ["create"] else prior,
            "after": None if actions == ["delete"] else values,
        }
    else:
        row["change"] = {
            "actions": actions,
            "before": before,
            "after": None if actions == ["delete"] else {},
        }
    return row


def provider_gap_projection(
    *,
    is_organization: bool,
    repositories: dict[str, dict] | None = None,
) -> dict:
    return {
        "schema_version": 1,
        "github_owner": INVENTORY_OWNER,
        "github_is_organization": is_organization,
        "organization_provider_gaps": (
            {
                "fork_pr_contributor_approval": PROVIDER_POLICY,
                "code_security_configuration": None,
            }
            if is_organization
            else None
        ),
        "repositories": repositories or {},
    }


def provider_gap_result(
    desired: dict,
    *,
    classification: str = "MATCH",
    reason: str = "policy-match",
    target_name: str | None = None,
    live_policy: str | None = PROVIDER_POLICY,
) -> dict:
    if target_name is None:
        target = INVENTORY_OWNER
        kind = "organization"
        declared = PROVIDER_POLICY
    else:
        repository = desired["repositories"][target_name]
        target = f"{INVENTORY_OWNER}/{target_name}"
        kind = "repository"
        declared = (
            None
            if repository["provider_gaps"] is None
            else repository["provider_gaps"]["fork_pr_contributor_approval"]
        )
    row = {
        "target_kind": kind,
        "target": target,
        "field": "fork_pr_contributor_approval",
        "classification": classification,
        "declared_policy": declared,
        "live_policy": live_policy,
        "reason": reason,
    }
    return provider_gaps.result_document([row])


def organization_gap_documents(
    classification: str | None = None,
) -> tuple[dict, dict]:
    repositories = {}
    rows = [
        {
            "target_kind": "organization",
            "target": INVENTORY_OWNER,
            "field": "fork_pr_contributor_approval",
            "classification": "MATCH",
            "declared_policy": PROVIDER_POLICY,
            "live_policy": PROVIDER_POLICY,
            "reason": "policy-match",
        }
    ]
    if classification is not None:
        name = "gap-public"
        declared = PROVIDER_POLICY
        live = PROVIDER_POLICY
        reason = "policy-match"
        if classification == "DRIFT":
            declared = OTHER_PROVIDER_POLICY
            reason = "policy-mismatch"
        elif classification == "INDETERMINATE":
            live = None
            reason = "http-403"
        elif classification == "NOT-APPLICABLE":
            name = "gap-private"
            declared = None
            live = None
            reason = "private-repository"
        repositories[name] = {
            "name": name,
            "visibility": "private" if classification == "NOT-APPLICABLE" else "public",
            "archived": False,
            "provider_gaps": (
                None
                if declared is None
                else {"fork_pr_contributor_approval": declared}
            ),
        }
        rows.append(
            {
                "target_kind": "repository",
                "target": f"{INVENTORY_OWNER}/{name}",
                "field": "fork_pr_contributor_approval",
                "classification": classification,
                "declared_policy": declared,
                "live_policy": live,
                "reason": reason,
            }
        )
    desired = provider_gap_projection(
        is_organization=True,
        repositories=repositories,
    )
    results = provider_gaps.result_document(rows)
    provider_gaps.validate_results(results, desired)
    return desired, results


def inventory_check(status: str = "pass", message: str | None = None) -> dict:
    instance = {
        "address": {"to_display": "check.inventory_complete"},
        "status": status,
    }
    if status == "fail":
        instance["problems"] = [
            {
                "message": message
                or "Live repositories not declared in the inventory:\npublic-inventory-canary"
            }
        ]
    return {
        "address": {
            "kind": "check",
            "name": "inventory_complete",
            "to_display": "check.inventory_complete",
        },
        "status": status,
        "instances": [instance],
    }


def inventory_data_row(name: str, names: list[str]) -> dict:
    return {
        "address": f'data.github_repositories.{name}["{INVENTORY_OWNER}"]',
        "mode": "data",
        "type": "github_repositories",
        "name": name,
        "index": INVENTORY_OWNER,
        "values": {"names": names},
    }


def boundary_inventory_checks() -> dict[str, list[object]]:
    malformed = inventory_check()
    malformed["address"] = "check.inventory_complete"
    return {
        "failing": [inventory_check("fail")],
        "missing": [],
        "malformed": [malformed],
    }


class WorkflowPredicateTests(unittest.TestCase):
    EXPECTED = {
        "Require read-only AWS role": (
            "${{ inputs.plan_only || (inputs.drift_issue && !inputs.plan_only && !inputs.apply) }}"
        ),
        "Terraform init (S3 backend)": (
            "${{ !(inputs.drift_issue && !inputs.plan_only && !inputs.apply) }}"
        ),
        "Terraform init (ETag-stripped local backend)": (
            "${{ inputs.drift_issue && !inputs.plan_only && !inputs.apply }}"
        ),
        "Adopt existing repositories into state": (
            "${{ !inputs.plan_only && !(inputs.drift_issue && !inputs.plan_only && !inputs.apply) }}"
        ),
        "Adopt existing repository rulesets into state": (
            "${{ !inputs.plan_only && !(inputs.drift_issue && !inputs.plan_only && !inputs.apply) }}"
        ),
        "Adopt existing organization settings into state": (
            "${{ inputs.github_is_organization && !inputs.plan_only && !(inputs.drift_issue && !inputs.plan_only && !inputs.apply) }}"
        ),
        "Guard repository destroys": (
            "${{ !(inputs.drift_issue && !inputs.plan_only && !inputs.apply) }}"
        ),
        "Verify provider gaps": (
            "${{ inputs.drift_issue && !inputs.plan_only && !inputs.apply }}"
        ),
        "Report drift as an issue": (
            "${{ always() && inputs.drift_issue && !inputs.plan_only && !inputs.apply }}"
        ),
        "Enforce provider-gap verification result": (
            "${{ always() && inputs.drift_issue && !inputs.plan_only && !inputs.apply }}"
        ),
        "Terraform apply": "${{ inputs.apply && !inputs.plan_only && !inputs.drift_issue }}",
    }

    def test_named_steps_have_exact_predicates(self):
        for name, expected in self.EXPECTED.items():
            with self.subTest(step=name):
                self.assertEqual(step_if(name), expected)

        credentials = step_block("Initialize temporary AWS credentials (OIDC)")
        role = re.search(r"(?m)^          role-to-assume: >-\n            (.+)$", credentials)
        self.assertIsNotNone(role)
        self.assertEqual(
            role.group(1),
            "${{ (inputs.plan_only || (inputs.drift_issue && !inputs.plan_only && !inputs.apply)) && secrets.aws_plan_role_arn || secrets.aws_role_arn }}",
        )

    def test_all_eight_mode_rows_from_shipped_predicates(self):
        predicates = {name: step_if(name) for name in self.EXPECTED}
        expected_rows = {
            # (plan_only, apply, drift_issue):
            # read-only role, imports, guard, local backend, verifier, reporter, gate, apply
            (False, False, False): (False, True, True, False, False, False, False, False),
            (False, False, True): (True, False, False, True, True, True, True, False),
            (False, True, False): (False, True, True, False, False, False, False, True),
            (False, True, True): (False, True, True, False, False, False, False, False),
            (True, False, False): (True, False, True, False, False, False, False, False),
            (True, False, True): (True, False, True, False, False, False, False, False),
            (True, True, False): (True, False, True, False, False, False, False, False),
            (True, True, True): (True, False, True, False, False, False, False, False),
        }
        evaluated_rows = {}

        for plan_only, apply, drift_issue in itertools.product((False, True), repeat=3):
            values = {
                name: eval_predicate(
                    expression,
                    plan_only=plan_only,
                    apply=apply,
                    drift_issue=drift_issue,
                )
                for name, expression in predicates.items()
            }
            actual = (
                values["Require read-only AWS role"],
                values["Adopt existing repositories into state"],
                values["Guard repository destroys"],
                values["Terraform init (ETag-stripped local backend)"],
                values["Verify provider gaps"],
                values["Report drift as an issue"],
                values["Enforce provider-gap verification result"],
                values["Terraform apply"],
            )
            row = (plan_only, apply, drift_issue)
            evaluated_rows[row] = actual
            with self.subTest(row=row):
                self.assertEqual(actual, expected_rows[row])
                self.assertEqual(
                    values["Adopt existing repository rulesets into state"], actual[1]
                )
                self.assertEqual(
                    values["Adopt existing organization settings into state"], actual[1]
                )
                self.assertEqual(
                    values["Terraform init (S3 backend)"], not actual[3]
                )
                self.assertFalse(actual[5] and (not actual[3] or actual[2]))
                self.assertEqual(actual[4], actual[5])
                self.assertEqual(actual[5], actual[6])

        invalid = (False, True, True)
        self.assertFalse(evaluated_rows[invalid][3], "invalid pair must not select detector")
        self.assertFalse(evaluated_rows[invalid][4], "invalid pair must not verify provider gaps")
        self.assertFalse(evaluated_rows[invalid][7], "invalid pair must not apply")

        self.assertNotIn("if:", step_block("Extract provider-gap desired state"))
        self.assertNotIn("if:", step_block("Publish sanitized plan summary to job summary"))


class ShippedInitTests(unittest.TestCase):
    def setUp(self):
        self.script = step_run("Terraform init (ETag-stripped local backend)")

    def test_shipped_init_strips_state_and_uses_bare_local_backend_init(self):
        state = {
            "version": 4,
            "resources": [
                {
                    "type": "github_repository",
                    "instances": [{"attributes": {"name": "fixture", "etag": 'W/"repo"'}}],
                },
                {
                    "type": "github_repository_ruleset",
                    "instances": [{"attributes": {"name": "rules", "etag": 'W/"rule"'}}],
                },
            ],
        }
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            source = tmp / "source.tfstate"
            source.write_text(json.dumps(state), encoding="utf-8")
            call_log = tmp / "calls.jsonl"

            aws_stub = tmp / "aws_stub.py"
            aws_stub.write_text(
                """
import json, os, shutil, sys
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"tool": "aws", "args": args}) + "\\n")
if args[:2] != ["s3", "cp"]:
    raise SystemExit(2)
shutil.copyfile(os.environ["SOURCE_STATE"], args[3])
""",
                encoding="utf-8",
            )
            terraform_stub = tmp / "terraform_stub.py"
            terraform_stub.write_text(
                """
import json, os, sys
with open(os.environ["CALL_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"tool": "terraform", "args": sys.argv[1:]}) + "\\n")
""",
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "CALL_LOG": str(call_log),
                    "SOURCE_STATE": str(source),
                    "AWS_STUB": str(aws_stub),
                    "TERRAFORM_STUB": str(terraform_stub),
                    "BACKEND_BUCKET": "fixture-bucket",
                    "TF_VAR_github_owner": "NWarila",
                    "GITHUB_REPOSITORY": "NWarila/github-terraform-runner",
                }
            )
            wrapped = f"""
aws() {{ "{sys.executable}" "$AWS_STUB" "$@"; }}
terraform() {{ "{sys.executable}" "$TERRAFORM_STUB" "$@"; }}
{self.script}
"""
            proc = subprocess.run(
                ["bash", "-c", wrapped], cwd=tmp, env=env,
                capture_output=True, text=True
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)

            stripped = json.loads((tmp / "stripped.tfstate").read_text(encoding="utf-8"))
            attributes = [
                instance["attributes"]
                for resource in stripped["resources"]
                for instance in resource["instances"]
            ]
            self.assertTrue(all("etag" not in item for item in attributes))
            self.assertFalse((tmp / "canonical.tfstate").exists())
            self.assertEqual(
                (tmp / "backend_override.tf").read_text(encoding="utf-8"),
                'terraform {\n  backend "local" {\n    path = "stripped.tfstate"\n  }\n}\n',
            )

            calls = [json.loads(line) for line in call_log.read_text().splitlines()]
            self.assertEqual(
                calls[0],
                {
                    "tool": "aws",
                    "args": [
                        "s3", "cp",
                        "s3://fixture-bucket/nwarila/github-terraform-runner/terraform.tfstate",
                        "canonical.tfstate", "--only-show-errors",
                    ],
                },
            )
            self.assertEqual(calls[1], {"tool": "terraform", "args": ["init"]})

    def test_strip_postcondition_rejects_a_remaining_etag_and_invalid_json(self):
        match = re.search(r"if ! jq -e \\\n\s+'([^']+)'", self.script)
        self.assertIsNotNone(match, "shipped jq postcondition is missing")
        jq_filter = match.group(1)
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            still_tagged = tmp / "still-tagged.tfstate"
            still_tagged.write_text(
                json.dumps(
                    {
                        "resources": [
                            {"instances": [{"attributes": {"etag": 'W/"still-here"'}}]}
                        ]
                    }
                ),
                encoding="utf-8",
            )
            invalid = tmp / "invalid.tfstate"
            invalid.write_text("{", encoding="utf-8")
            for path in (still_tagged, invalid):
                with self.subTest(path=path.name):
                    proc = subprocess.run(
                        ["jq", "-e", jq_filter, str(path)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    )
                    self.assertNotEqual(proc.returncode, 0)


class InventoryVerboseRedactionTests(unittest.TestCase):
    def test_expected_check_warning_redacts_owner_only_name_on_both_streams(self):
        env = os.environ.copy()
        for key in (
            "GH_TOKEN",
            "GITHUB_TOKEN",
            "GITHUB_OWNER",
            "GITHUB_ORGANIZATION",
            "TF_VAR_github_token",
            "TF_CLI_ARGS",
            "TF_CLI_ARGS_test",
        ):
            env.pop(key, None)
        proc = subprocess.run(
            [
                "terraform",
                "test",
                "-filter=tests/inventory.tftest.hcl",
                "-verbose",
                "-no-color",
            ],
            cwd=ROOT / "terraform",
            env=env,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, "credential-free inventory test failed")
        combined = proc.stdout + proc.stderr
        self.assertIn("<1 non-public repositories redacted>", combined)
        self.assertNotIn(NON_PUBLIC_SENTINEL, proc.stdout)
        self.assertNotIn(NON_PUBLIC_SENTINEL, proc.stderr)


class ReporterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reporter = step_run("Report drift as an issue")
        cls.guard = step_run("Guard repository destroys")
        cls.summary = step_run("Publish sanitized plan summary to job summary")
        cls.gate = step_run("Enforce provider-gap verification result")

    @staticmethod
    def stage_provider_gap_tool(root: Path) -> Path:
        tool_directory = root / "framework" / "tools"
        tool_directory.mkdir(parents=True)
        shutil.copyfile(
            ROOT / "tools" / "verify_provider_gaps.py",
            tool_directory / "verify_provider_gaps.py",
        )
        terraform_directory = root / "framework" / "terraform"
        terraform_directory.mkdir()
        return terraform_directory

    def run_reporter(self, changes: list[dict], *, existing: str = "",
                     resource_drift: list[dict] | None = None) -> tuple[list[dict], str]:
        with tempfile.TemporaryDirectory() as raw_tmp:
            root = Path(raw_tmp)
            tmp = self.stage_provider_gap_tool(root)
            (tmp / "plan.json").write_text(
                json.dumps(
                    {
                        "resource_changes": changes,
                        "resource_drift": resource_drift or [],
                        "checks": [inventory_check()],
                        "prior_state": {"values": {"root_module": {"resources": []}}},
                        "planned_values": {"root_module": {"resources": []}},
                        "raw_plan_marker": RAW_PLAN_SENTINEL,
                    }
                ),
                encoding="utf-8",
            )
            desired = provider_gap_projection(is_organization=False)
            (tmp / "provider-gap-desired-state.json").write_text(
                json.dumps(desired), encoding="utf-8"
            )
            (tmp / "provider-gap-results.json").write_text(
                json.dumps(provider_gaps.result_document([])), encoding="utf-8"
            )
            gh_log = tmp / "gh.jsonl"
            gh_stub = tmp / "gh_stub.py"
            gh_stub.write_text(
                """
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
record = {"args": args}
if "--body-file" in args:
    record["body"] = Path(args[args.index("--body-file") + 1]).read_text(encoding="utf-8")
with open(os.environ["GH_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record) + "\\n")
if args[:2] == ["issue", "list"] and os.environ.get("EXISTING_ISSUE"):
    print(os.environ["EXISTING_ISSUE"])
""",
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "GH_LOG": str(gh_log),
                    "GH_STUB": str(gh_stub),
                    "EXISTING_ISSUE": existing,
                    "GH_TOKEN": "stub-token",
                    "REPO": "example/caller",
                    "RUN_URL": "https://example.invalid/actions/runs/1",
                    "TF_VAR_github_is_organization": "false",
                    "TF_VAR_github_owner": INVENTORY_OWNER,
                }
            )
            wrapped = f"""
gh() {{ "{sys.executable}" "$GH_STUB" "$@"; }}
{self.reporter}
"""
            proc = subprocess.run(
                ["bash", "-c", wrapped], cwd=tmp, env=env,
                capture_output=True, text=True
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            records = (
                [json.loads(line) for line in gh_log.read_text().splitlines()]
                if gh_log.exists() else []
            )
            return records, proc.stdout

    def run_inventory_projections(
        self,
        *,
        checks: list[object] | None = None,
        owner_names: list[str] | None = None,
        public_names: list[str] | None = None,
        metadata: dict | str | None = None,
        curl_mode: str = "ok",
        changes: list[dict] | None = None,
        existing: str = "",
        prior_resources: list[object] | None = None,
        is_organization: bool = True,
        detector_mode: bool = True,
        desired_state: dict | str | None = None,
        gap_results: dict | str | None = None,
    ) -> tuple[list[dict], str, str, int, list[list[str]]]:
        owner_names = owner_names if owner_names is not None else ["declared-public"]
        public_names = public_names if public_names is not None else ["declared-public"]
        if prior_resources is None:
            prior_resources = [
                inventory_data_row("owner", owner_names),
                inventory_data_row("public", public_names),
            ]
        if metadata is None:
            metadata = {
                "public_repos": len(set(public_names)),
                "total_private_repos": len(set(owner_names)) - len(set(public_names)),
            }
        metadata_body = metadata if isinstance(metadata, str) else json.dumps(metadata)
        plan = {
            "resource_changes": changes or [],
            "resource_drift": [],
            "checks": checks if checks is not None else [inventory_check()],
            "prior_state": {"values": {"root_module": {"resources": prior_resources}}},
            "planned_values": {"root_module": {"resources": []}},
            "raw_plan_marker": RAW_PLAN_SENTINEL,
        }

        with tempfile.TemporaryDirectory() as raw_tmp:
            root = Path(raw_tmp)
            tmp = self.stage_provider_gap_tool(root)
            (tmp / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
            desired = (
                provider_gap_projection(is_organization=is_organization)
                if desired_state is None
                else desired_state
            )
            desired_text = desired if isinstance(desired, str) else json.dumps(desired)
            (tmp / "provider-gap-desired-state.json").write_text(
                desired_text, encoding="utf-8"
            )
            if detector_mode:
                if gap_results is None:
                    if is_organization:
                        results_value = provider_gap_result(desired)
                    else:
                        results_value = provider_gaps.result_document([])
                else:
                    results_value = gap_results
                results_text = (
                    results_value
                    if isinstance(results_value, str)
                    else json.dumps(results_value)
                )
                (tmp / "provider-gap-results.json").write_text(
                    results_text, encoding="utf-8"
                )
            summary_file = tmp / "summary.md"
            gh_log = tmp / "gh.jsonl"
            curl_log = tmp / "curl.log"

            curl_stub = tmp / "curl_stub.py"
            curl_stub.write_text(
                """
import json, os, sys
from pathlib import Path
with open(os.environ["CURL_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(sys.argv[1:]) + "\\n")
if os.environ["CURL_MODE"] == "fail":
    raise SystemExit(22)
if os.environ["CURL_MODE"] == "timeout":
    raise SystemExit(28)
args = sys.argv[1:]
output = args[args.index("--output") + 1]
Path(output).write_text(os.environ["METADATA_BODY"], encoding="utf-8")
""",
                encoding="utf-8",
            )
            gh_stub = tmp / "gh_stub.py"
            gh_stub.write_text(
                """
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
record = {"args": args}
if "--body-file" in args:
    record["body"] = Path(args[args.index("--body-file") + 1]).read_text(encoding="utf-8")
with open(os.environ["GH_LOG"], "a", encoding="utf-8") as fh:
    fh.write(json.dumps(record) + "\\n")
if args[:2] == ["issue", "list"] and os.environ.get("EXISTING_ISSUE"):
    print(os.environ["EXISTING_ISSUE"])
""",
                encoding="utf-8",
            )
            env = os.environ.copy()
            env.update(
                {
                    "CURL_LOG": str(curl_log),
                    "CURL_MODE": curl_mode,
                    "CURL_STUB": str(curl_stub),
                    "METADATA_BODY": metadata_body,
                    "GH_LOG": str(gh_log),
                    "GH_STUB": str(gh_stub),
                    "EXISTING_ISSUE": existing,
                    "GITHUB_STEP_SUMMARY": str(summary_file),
                    "GH_TOKEN": "actions-issue-token-sentinel-7f3",
                    "REPO": "example/caller",
                    "RUN_URL": "https://example.invalid/actions/runs/1",
                    "DETECTOR_MODE": "true" if detector_mode else "false",
                    "TF_VAR_github_is_organization": (
                        "true" if is_organization else "false"
                    ),
                    "TF_VAR_github_owner": INVENTORY_OWNER,
                    "TF_VAR_github_token": TOKEN_SENTINEL,
                }
            )
            summary_wrapped = f"""
curl() {{ "{sys.executable}" "$CURL_STUB" "$@"; }}
{self.summary}
"""
            summary_proc = subprocess.run(
                ["bash", "-c", summary_wrapped],
                cwd=tmp,
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(summary_proc.returncode, 0, "summary projection failed")

            reporter_stdout = ""
            reporter_stderr = ""
            if detector_mode:
                reporter_wrapped = f"""
gh() {{ "{sys.executable}" "$GH_STUB" "$@"; }}
{self.reporter}
"""
                reporter_proc = subprocess.run(
                    ["bash", "-c", reporter_wrapped],
                    cwd=tmp,
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(
                    reporter_proc.returncode, 0, "reporter projection failed"
                )
                reporter_stdout = reporter_proc.stdout
                reporter_stderr = reporter_proc.stderr

            records = (
                [json.loads(line) for line in gh_log.read_text().splitlines()]
                if gh_log.exists() else []
            )
            summary = summary_file.read_text(encoding="utf-8")
            issue_bodies = "\n".join(
                record.get("body", "") for record in records
            )
            surfaces = "\n".join(
                (
                    summary_proc.stdout,
                    summary_proc.stderr,
                    reporter_stdout,
                    reporter_stderr,
                    summary,
                    issue_bodies,
                    json.dumps(records),
                )
            )
            curl_argv = (
                [json.loads(line) for line in curl_log.read_text().splitlines()]
                if curl_log.exists() else []
            )
            return records, summary, surfaces, len(curl_argv), curl_argv

    @staticmethod
    def command(records: list[dict], *prefix: str) -> dict:
        matches = [record for record in records if record["args"][:len(prefix)] == list(prefix)]
        if len(matches) != 1:
            raise AssertionError(f"expected one {prefix} command, got {matches}")
        return matches[0]

    def assert_nonempty_report(self, changes: list[dict], expected_classes: set[str],
                               *, existing: str = "") -> list[dict]:
        records, _ = self.run_reporter(changes, existing=existing)
        label = self.command(records, "label", "create")
        self.assertIn("--force", label["args"])
        self.assertEqual(
            label["args"][label["args"].index("--description") + 1], LABEL_DESCRIPTION
        )
        operation = "edit" if existing else "create"
        issue = self.command(records, "issue", operation)
        self.assertEqual(issue["args"][issue["args"].index("--title") + 1], TITLE)
        for classification in expected_classes:
            self.assertIn(classification, issue["body"])
        all_classes = {
            INDETERMINATE,
            DRIFT,
            INVENTORY_UNDECLARED,
            INVENTORY_UNVERIFIED,
        }
        for classification in all_classes - expected_classes:
            self.assertNotIn(classification, issue["body"])
        label_index = records.index(label)
        issue_index = records.index(issue)
        self.assertLess(label_index, issue_index)
        return records

    def test_create_only_is_indeterminate_and_opens(self):
        self.assert_nonempty_report(
            [change("github_repository.repo[\"new\"]", ["create"])],
            {INDETERMINATE},
        )

    def test_update_only_is_drift_and_migrates_existing_issue_title(self):
        records = self.assert_nonempty_report(
            [change("github_repository.repo[\"changed\"]", ["update"])],
            {DRIFT}, existing="42",
        )
        edit = self.command(records, "issue", "edit")
        self.assertEqual(edit["args"][2], "42")

    def test_delete_and_both_replacement_orders_are_drift(self):
        fixtures = {
            "delete": ["delete"],
            "replace-delete-create": ["delete", "create"],
            "replace-create-delete": ["create", "delete"],
        }
        for label, actions in fixtures.items():
            with self.subTest(fixture=label):
                self.assert_nonempty_report(
                    [change(f"github_repository.repo[\"{label}\"]", actions)], {DRIFT}
                )

    def test_mixed_plan_prints_both_classes(self):
        self.assert_nonempty_report(
            [
                change("github_repository.repo[\"unbound\"]", ["create"]),
                change("github_repository.repo[\"changed\"]", ["update"]),
            ],
            {INDETERMINATE, DRIFT},
        )

    def test_clean_plan_closes_existing_issue_and_ignores_refresh_drift(self):
        etag_only_drift = [
            change("github_repository.repo[\"clean\"]", ["update"])
        ]
        records, output = self.run_reporter(
            [change("github_repository.repo[\"clean\"]", ["no-op"])],
            existing="42",
            resource_drift=etag_only_drift,
        )
        self.command(records, "issue", "comment")
        close = self.command(records, "issue", "close")
        self.assertEqual(close["args"][2], "42")
        self.assertFalse(any(record["args"][:2] == ["label", "create"] for record in records))
        self.assertIn("drift resolved; closed #42", output)
        self.assertNotIn("resource_drift", step_run("Report drift as an issue"))

    def test_clean_plan_without_issue_is_a_noop(self):
        records, output = self.run_reporter([])
        self.assertEqual([record["args"][:2] for record in records], [["issue", "list"]])
        self.assertIn("no drift", output)

    def test_inventory_only_public_name_reaches_both_safe_projections(self):
        public_name = "public-inventory-canary"
        message = f"Live repositories not declared in the inventory:\n{public_name}"
        records, summary, surfaces, curl_calls, _ = self.run_inventory_projections(
            checks=[inventory_check("fail", message)],
            owner_names=["declared-public", public_name],
            public_names=["declared-public", public_name],
            metadata={
                "public_repos": 2,
                "total_private_repos": 0,
                "raw": RAW_BODY_SENTINEL,
            },
        )
        issue = self.command(records, "issue", "create")
        self.assertEqual(curl_calls, 1)
        self.assertIn(INVENTORY_UNDECLARED, summary)
        self.assertIn(INVENTORY_UNDECLARED, issue["body"])
        self.assertIn(public_name, summary)
        self.assertIn(public_name, issue["body"])
        self.assertEqual(summary.count(public_name), 1)
        self.assertEqual(issue["body"].count(public_name), 1)
        self.assertIn("No actionable Terraform resource changes", summary)
        self.assertIn("No actionable Terraform resource changes", issue["body"])
        self.assertNotIn("Infrastructure matches", surfaces)
        for secret in (
            NON_PUBLIC_SENTINEL,
            TOKEN_SENTINEL,
            RAW_BODY_SENTINEL,
            RAW_PLAN_SENTINEL,
            json.dumps(["declared-public", public_name]),
        ):
            self.assertNotIn(secret, surfaces)

    def test_terraform_only_and_mixed_findings_reach_both_projections(self):
        changed = change('github_repository.repo["changed"]', ["update"])
        records, summary, _, _, _ = self.run_inventory_projections(changes=[changed])
        issue = self.command(records, "issue", "create")
        self.assertIn('github_repository.repo["changed"]', summary)
        self.assertIn(DRIFT, issue["body"])
        self.assertNotIn(INVENTORY_UNDECLARED, issue["body"])
        self.assertNotIn(INVENTORY_UNVERIFIED, issue["body"])

        public_name = "public-inventory-canary"
        message = f"Live repositories not declared in the inventory:\n{public_name}"
        records, summary, _, _, _ = self.run_inventory_projections(
            checks=[inventory_check("fail", message)],
            owner_names=["declared-public", public_name],
            public_names=["declared-public", public_name],
            changes=[changed],
        )
        issue = self.command(records, "issue", "create")
        self.assertIn('github_repository.repo["changed"]', summary)
        self.assertIn(INVENTORY_UNDECLARED, summary)
        self.assertIn(DRIFT, issue["body"])
        self.assertIn(INVENTORY_UNDECLARED, issue["body"])

    def test_inventory_recovery_closes_only_when_both_planes_are_empty(self):
        records, summary, _, curl_calls, _ = self.run_inventory_projections(
            existing="42"
        )
        self.assertEqual(curl_calls, 1)
        self.assertIn("No actionable Terraform resource changes", summary)
        self.assertIn("No actionable inventory findings", summary)
        comment = self.command(records, "issue", "comment")
        self.assertIn(
            "Terraform resource changes, INVENTORY / undeclared-live, "
            "INVENTORY / enumeration-unverified, and provider-gap actionable "
            "findings are all empty",
            " ".join(comment["args"]),
        )
        self.command(records, "issue", "close")
        self.assertFalse(
            any(record["args"][:2] == ["label", "create"] for record in records)
        )

    def test_non_public_inventory_name_is_redacted_on_every_surface(self):
        message = (
            "Live repositories not declared in the inventory:\n"
            "<1 non-public repositories redacted>"
        )
        records, summary, surfaces, curl_calls, _ = self.run_inventory_projections(
            checks=[inventory_check("fail", message)],
            owner_names=["declared-public", NON_PUBLIC_SENTINEL],
            public_names=["declared-public"],
            metadata={"public_repos": 1, "total_private_repos": 1},
        )
        issue = self.command(records, "issue", "create")
        self.assertEqual(curl_calls, 1)
        self.assertIn("<1 non-public repositories redacted>", summary)
        self.assertIn("<1 non-public repositories redacted>", issue["body"])
        self.assertNotIn(NON_PUBLIC_SENTINEL, surfaces)
        self.assertNotIn(TOKEN_SENTINEL, surfaces)
        self.assertNotIn(RAW_PLAN_SENTINEL, surfaces)

    def test_metadata_get_and_body_failures_are_enumeration_unverified(self):
        cases = {
            "get-failure": {"curl_mode": "fail"},
            "malformed-json": {
                "metadata": f'{{"marker":"{RAW_BODY_SENTINEL}"',
            },
            "non-integer": {
                "metadata": {"public_repos": True, "total_private_repos": 0},
            },
            "negative": {
                "metadata": {"public_repos": -1, "total_private_repos": 2},
            },
        }
        for label, kwargs in cases.items():
            with self.subTest(case=label):
                records, summary, surfaces, curl_calls, _ = self.run_inventory_projections(
                    **kwargs
                )
                issue = self.command(records, "issue", "create")
                self.assertEqual(curl_calls, 1)
                self.assertIn(INVENTORY_UNVERIFIED, summary)
                self.assertIn(INVENTORY_UNVERIFIED, issue["body"])
                self.assertNotIn(RAW_BODY_SENTINEL, surfaces)
                self.assertNotIn(TOKEN_SENTINEL, surfaces)
                self.assertNotIn(RAW_PLAN_SENTINEL, surfaces)

    def test_invalid_search_rows_fail_closed_without_rendering_names(self):
        duplicate_owner = [
            inventory_data_row("owner", ["declared-public", NON_PUBLIC_SENTINEL,
                                          NON_PUBLIC_SENTINEL]),
            inventory_data_row("public", ["declared-public"]),
        ]
        duplicate_public = [
            inventory_data_row("owner", ["declared-public"]),
            inventory_data_row("public", ["declared-public", "declared-public"]),
        ]
        bad_subset = [
            inventory_data_row("owner", ["declared-public", NON_PUBLIC_SENTINEL]),
            inventory_data_row("public", ["public-absent-from-owner"]),
        ]
        missing_owner = [inventory_data_row("public", ["declared-public"])]
        missing_public = [inventory_data_row("owner", ["declared-public"])]
        duplicate_owner_rows = [
            inventory_data_row("owner", ["declared-public"]),
            inventory_data_row("owner", ["declared-public"]),
            inventory_data_row("public", ["declared-public"]),
        ]
        duplicate_public_rows = [
            inventory_data_row("owner", ["declared-public"]),
            inventory_data_row("public", ["declared-public"]),
            inventory_data_row("public", ["declared-public"]),
        ]
        non_string_name = [
            inventory_data_row("owner", ["declared-public", 7]),
            inventory_data_row("public", ["declared-public"]),
        ]
        missing_names = [
            inventory_data_row("owner", ["declared-public"]),
            {
                "mode": "data",
                "type": "github_repositories",
                "name": "public",
                "index": INVENTORY_OWNER,
                "values": {},
            },
        ]
        cases = {
            "duplicate-owner-name": duplicate_owner,
            "duplicate-public-name": duplicate_public,
            "public-not-subset": bad_subset,
            "missing-owner-row": missing_owner,
            "missing-public-row": missing_public,
            "duplicate-owner-row": duplicate_owner_rows,
            "duplicate-public-row": duplicate_public_rows,
            "non-string-name": non_string_name,
            "missing-names": missing_names,
        }
        for label, rows in cases.items():
            with self.subTest(case=label):
                records, summary, surfaces, _, _ = self.run_inventory_projections(
                    prior_resources=rows,
                    metadata={"public_repos": 1, "total_private_repos": 1},
                )
                issue = self.command(records, "issue", "create")
                self.assertIn(INVENTORY_UNVERIFIED, summary)
                self.assertIn(INVENTORY_UNVERIFIED, issue["body"])
                for secret in (
                    NON_PUBLIC_SENTINEL,
                    "public-absent-from-owner",
                    TOKEN_SENTINEL,
                    RAW_PLAN_SENTINEL,
                ):
                    self.assertNotIn(secret, surfaces)

    def test_metadata_count_mismatch_and_search_ceiling_fail_closed(self):
        records, summary, _, _, _ = self.run_inventory_projections(
            metadata={"public_repos": 1, "total_private_repos": 1}
        )
        issue = self.command(records, "issue", "create")
        self.assertIn(INVENTORY_UNVERIFIED, summary)
        self.assertIn(INVENTORY_UNVERIFIED, issue["body"])

        names_999 = [f"repo-{number:04d}" for number in range(999)]
        records, summary, surfaces, _, _ = self.run_inventory_projections(
            owner_names=names_999,
            public_names=names_999,
            metadata={"public_repos": 999, "total_private_repos": 0},
        )
        self.assertEqual([record["args"][:2] for record in records], [["issue", "list"]])
        self.assertIn("No actionable inventory findings", summary)
        self.assertNotIn(INVENTORY_UNVERIFIED, surfaces)

        names_1000 = [f"repo-{number:04d}" for number in range(1000)]
        records, summary, _, _, _ = self.run_inventory_projections(
            owner_names=names_1000,
            public_names=names_1000,
            metadata={"public_repos": 1000, "total_private_repos": 0},
        )
        issue = self.command(records, "issue", "create")
        self.assertIn(INVENTORY_UNVERIFIED, summary)
        self.assertIn(INVENTORY_UNVERIFIED, issue["body"])

    def test_malformed_missing_duplicate_and_unsupported_checks_fail_closed(self):
        unknown = inventory_check()
        unknown["status"] = "unknown"
        unknown["instances"][0]["status"] = "unknown"
        unsupported = inventory_check()
        unsupported["status"] = "pending"
        unsupported["instances"][0]["status"] = "pending"
        inconsistent = inventory_check("fail")
        inconsistent["instances"][0]["status"] = "pass"
        missing_message = inventory_check("fail")
        missing_message["instances"][0]["problems"] = [{}]
        non_string_message = inventory_check("fail")
        non_string_message["instances"][0]["problems"] = [{"message": 7}]
        pass_with_problem = inventory_check()
        pass_with_problem["instances"][0]["problems"] = [
            {"message": "unexpected pass problem"}
        ]
        malformed = inventory_check()
        malformed["address"] = "check.inventory_complete"
        cases = {
            "missing": [],
            "duplicate": [inventory_check(), inventory_check()],
            "malformed": [malformed],
            "unknown": [unknown],
            "unsupported": [unsupported],
            "inconsistent": [inconsistent],
            "missing-message": [missing_message],
            "non-string-message": [non_string_message],
            "pass-with-problem": [pass_with_problem],
        }
        for label, checks in cases.items():
            with self.subTest(case=label):
                records, summary, surfaces, _, _ = self.run_inventory_projections(
                    checks=checks
                )
                issue = self.command(records, "issue", "create")
                self.assertIn(INVENTORY_UNVERIFIED, summary)
                self.assertIn(INVENTORY_UNVERIFIED, issue["body"])
                self.assertNotIn(RAW_PLAN_SENTINEL, surfaces)
                self.assertNotIn(TOKEN_SENTINEL, surfaces)

    def test_non_detector_modes_do_not_classify_inventory(self):
        modes = {
            "pr-plan-only": {"plan_only": True, "apply": False, "drift_issue": True},
            "ordinary-dispatch": {"plan_only": False, "apply": False, "drift_issue": False},
            "applying-dispatch": {"plan_only": False, "apply": True, "drift_issue": False},
        }
        reporter_predicate = step_if("Report drift as an issue")
        for mode, inputs in modes.items():
            reporter_runs = eval_predicate(
                reporter_predicate,
                github_is_organization=True,
                **inputs,
            )
            self.assertFalse(reporter_runs)
            for check_case, checks in boundary_inventory_checks().items():
                with self.subTest(mode=mode, check=check_case):
                    records, summary, surfaces, curl_calls, curl_argv = (
                        self.run_inventory_projections(
                            checks=checks,
                            is_organization=True,
                            detector_mode=reporter_runs,
                        )
                    )
                    self.assertEqual(records, [])
                    self.assertEqual(curl_calls, 0)
                    self.assertEqual(curl_argv, [])
                    self.assertNotIn("INVENTORY /", summary)
                    self.assertNotIn("INVENTORY /", surfaces)

    def test_personal_detector_empty_projection_ignores_inventory_check(self):
        for check_case, checks in boundary_inventory_checks().items():
            with self.subTest(check=check_case):
                records, summary, surfaces, curl_calls, curl_argv = (
                    self.run_inventory_projections(
                        checks=checks,
                        is_organization=False,
                    )
                )
                self.assertEqual(
                    [record["args"][:2] for record in records],
                    [["issue", "list"]],
                )
                self.assertEqual(curl_calls, 0)
                self.assertEqual(curl_argv, [])
                self.assertNotIn("INVENTORY /", summary)
                self.assertNotIn("INVENTORY /", surfaces)
                self.assertFalse(
                    any(
                        record["args"][:2] in (["issue", "create"], ["issue", "edit"])
                        for record in records
                    )
                )

    def test_personal_detector_terraform_only_projection_ignores_inventory_check(self):
        changed = change('github_repository.repo["changed"]', ["update"])
        for check_case, checks in boundary_inventory_checks().items():
            with self.subTest(check=check_case):
                records, summary, surfaces, curl_calls, curl_argv = (
                    self.run_inventory_projections(
                        checks=checks,
                        changes=[changed],
                        is_organization=False,
                    )
                )
                issue = self.command(records, "issue", "create")
                self.assertEqual(curl_calls, 0)
                self.assertEqual(curl_argv, [])
                self.assertIn('github_repository.repo["changed"]', summary)
                self.assertIn(DRIFT, issue["body"])
                self.assertNotIn("INVENTORY /", summary)
                self.assertNotIn("INVENTORY /", issue["body"])
                self.assertNotIn("INVENTORY /", surfaces)

    def test_metadata_timeout_has_exact_argv_and_reaches_both_projections(self):
        records, summary, surfaces, curl_calls, curl_argv = (
            self.run_inventory_projections(curl_mode="timeout")
        )
        issue = self.command(records, "issue", "create")
        self.assertEqual(curl_calls, 1)
        self.assertEqual(len(curl_argv), 1)
        args = curl_argv[0]
        self.assertEqual(args.count("--max-time"), 1)
        max_time_index = args.index("--max-time")
        self.assertLess(max_time_index + 1, len(args))
        self.assertEqual(args[max_time_index + 1], "30")
        self.assertIn(INVENTORY_UNVERIFIED, summary)
        self.assertIn(INVENTORY_UNVERIFIED, issue["body"])
        self.assertNotIn(TOKEN_SENTINEL, surfaces)
        self.assertNotIn(RAW_PLAN_SENTINEL, surfaces)

    def test_inventory_metadata_request_is_one_read_only_get_with_terraform_pat(self):
        summary = self.summary
        self.assertIn("curl --request GET", summary)
        self.assertIn("--max-time 30", summary)
        self.assertIn("Authorization: Bearer ${TF_VAR_github_token}", summary)
        self.assertIn("https://api.github.com/orgs/${TF_VAR_github_owner}", summary)
        self.assertNotIn("GH_TOKEN=", summary)
        self.assertIn(
            "GH_TOKEN: ${{ github.token }}",
            step_block("Report drift as an issue"),
        )

        records, rendered, surfaces, curl_calls, _ = self.run_inventory_projections(
            prior_resources=[],
            is_organization=False,
        )
        self.assertEqual(curl_calls, 0)
        self.assertEqual([record["args"][:2] for record in records], [["issue", "list"]])
        self.assertNotIn("INVENTORY /", rendered)
        self.assertNotIn(INVENTORY_UNVERIFIED, surfaces)

    def test_refused_delete_still_reaches_reporter_in_detector_mode(self):
        refused = change(
            "github_repository.repo[\"doomed\"]",
            ["delete"],
            before={"archived": False, "archive_on_destroy": False},
        )
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            (tmp / "plan.json").write_text(
                json.dumps({"resource_changes": [refused]}), encoding="utf-8"
            )
            guard = subprocess.run(
                ["bash", "-c", self.guard], cwd=tmp,
                capture_output=True, text=True
            )
        self.assertEqual(guard.returncode, 1)
        self.assertIn("REFUSING TO DELETE REPOSITORIES", guard.stdout)

        self.assertFalse(
            eval_predicate(
                step_if("Guard repository destroys"),
                plan_only=False, apply=False, drift_issue=True,
            )
        )
        self.assert_nonempty_report([refused], {DRIFT})

    def test_three_plane_reporter_matrix_and_issue_lifecycle(self):
        public_name = "public-inventory-canary"
        inventory_message = (
            "Live repositories not declared in the inventory:\n" + public_name
        )
        tf_change = change('github_repository.repo["changed"]', ["update"])
        cases = {
            "tf-clean-gap-drift": {
                "gap": "DRIFT",
                "expected": {"gap"},
            },
            "tf-drift-gap-clean": {
                "changes": [tf_change],
                "expected": {"terraform"},
            },
            "inventory-actionable-gap-clean": {
                "checks": [inventory_check("fail", inventory_message)],
                "expected": {"inventory"},
            },
            "inventory-clean-gap-actionable": {
                "gap": "INDETERMINATE",
                "expected": {"gap"},
            },
            "inventory-gap-mixed": {
                "checks": [inventory_check("fail", inventory_message)],
                "gap": "DRIFT",
                "expected": {"inventory", "gap"},
            },
            "all-three-mixed": {
                "changes": [tf_change],
                "checks": [inventory_check("fail", inventory_message)],
                "gap": "INDETERMINATE",
                "expected": {"terraform", "inventory", "gap"},
            },
            "not-applicable-only": {
                "gap": "NOT-APPLICABLE",
                "expected": set(),
            },
            "all-three-clean": {
                "expected": set(),
            },
        }
        for label, fixture in cases.items():
            with self.subTest(case=label):
                desired, results = organization_gap_documents(fixture.get("gap"))
                records, summary, surfaces, _, _ = self.run_inventory_projections(
                    changes=fixture.get("changes"),
                    checks=fixture.get("checks"),
                    existing="42",
                    desired_state=desired,
                    gap_results=results,
                )
                expected = fixture["expected"]
                commands = [record["args"][:2] for record in records]
                if expected:
                    self.assertIn(["issue", "edit"], commands)
                    self.assertNotIn(["issue", "close"], commands)
                    self.assertNotIn("Infrastructure matches", summary)
                else:
                    self.assertIn(["issue", "comment"], commands)
                    self.assertIn(["issue", "close"], commands)
                    self.assertNotIn(["issue", "edit"], commands)
                    self.assertIn("Infrastructure matches", summary)
                if "terraform" in expected:
                    self.assertIn('github_repository.repo["changed"]', surfaces)
                if "inventory" in expected:
                    self.assertIn(INVENTORY_UNDECLARED, surfaces)
                if "gap" in expected:
                    self.assertRegex(surfaces, r"(?:DRIFT|INDETERMINATE).*(?:policy-mismatch|http-403)")
                self.assertNotIn(PROVIDER_POLICY, surfaces)
                self.assertNotIn(OTHER_PROVIDER_POLICY, surfaces)

    def test_state_only_private_delete_addresses_are_redacted_in_both_modes(self):
        private_name = "state-only-private-sentinel-7f2"
        repository_address = f'github_repository.repo["{private_name}"]'
        dependent_address = f'github_repository_file.codeowners["{private_name}"]'
        prior_resources = [
            inventory_data_row("owner", ["declared-public", private_name]),
            inventory_data_row("public", ["declared-public"]),
            {
                "address": repository_address,
                "mode": "managed",
                "type": "github_repository",
                "name": "repo",
                "index": private_name,
                "values": {"name": private_name, "visibility": "private"},
            },
        ]
        changes = [
            change(dependent_address, ["delete"], resource_type="github_repository_file"),
            change(
                repository_address,
                ["delete"],
                before={"visibility": "private", "archived": True},
            ),
        ]
        for detector_mode in (False, True):
            with self.subTest(detector=detector_mode):
                records, summary, surfaces, _, _ = self.run_inventory_projections(
                    changes=changes,
                    owner_names=["declared-public", private_name],
                    public_names=["declared-public"],
                    prior_resources=prior_resources,
                    detector_mode=detector_mode,
                )
                self.assertIn(provider_gaps.PRIVATE_RESOURCE_REDACTED, summary)
                self.assertNotIn(private_name, surfaces)
                self.assertNotIn(repository_address, surfaces)
                self.assertNotIn(dependent_address, surfaces)
                if detector_mode:
                    issue = self.command(records, "issue", "create")
                    self.assertIn(provider_gaps.PRIVATE_RESOURCE_REDACTED, issue["body"])
                else:
                    self.assertEqual(records, [])

    def test_private_provider_target_indeterminate_is_redacted_on_every_surface(self):
        private_name = PRIVATE_PROVIDER_SENTINEL
        desired = provider_gap_projection(
            is_organization=True,
            repositories={
                private_name: {
                    "name": private_name,
                    "visibility": "private",
                    "archived": False,
                    "provider_gaps": None,
                }
            },
        )
        results = provider_gaps.result_document(
            [
                {
                    "target_kind": "organization",
                    "target": INVENTORY_OWNER,
                    "field": "fork_pr_contributor_approval",
                    "classification": "MATCH",
                    "declared_policy": PROVIDER_POLICY,
                    "live_policy": PROVIDER_POLICY,
                    "reason": "policy-match",
                },
                {
                    "target_kind": "repository",
                    "target": f"{INVENTORY_OWNER}/{private_name}",
                    "field": "fork_pr_contributor_approval",
                    "classification": "INDETERMINATE",
                    "declared_policy": None,
                    "live_policy": None,
                    "reason": "http-403",
                },
            ]
        )
        provider_gaps.validate_results(results, desired)
        records, summary, surfaces, _, _ = self.run_inventory_projections(
            desired_state=desired,
            gap_results=results,
        )
        issue = self.command(records, "issue", "create")
        self.assertIn(provider_gaps.PRIVATE_REPOSITORY_REDACTED, summary)
        self.assertIn(provider_gaps.PRIVATE_REPOSITORY_REDACTED, issue["body"])
        self.assertNotIn(private_name, surfaces)
        self.assertNotIn(PROVIDER_POLICY, surfaces)

    def test_final_gate_accepts_only_explicit_decimal_zero(self):
        cases = {
            "missing": (None, 1),
            "empty": ("", 1),
            "malformed": ("zero", 1),
            "negative": ("-1", 1),
            "leading-zero": ("00", 1),
            "nonzero": ("1", 1),
            "zero": ("0", 0),
        }
        for label, (value, expected) in cases.items():
            with self.subTest(case=label):
                env = os.environ.copy()
                if value is None:
                    env.pop("VERIFIER_EXIT_CODE", None)
                else:
                    env["VERIFIER_EXIT_CODE"] = value
                proc = subprocess.run(
                    ["bash", "-c", self.gate],
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(proc.returncode, expected)

    def test_detector_input_failure_and_unsafe_redaction_never_close_issue(self):
        desired = provider_gap_projection(is_organization=False)
        results = provider_gaps.result_document([])
        unsafe_name = "unsafe-private-sentinel-7f2"
        cases = {
            "malformed-results": (
                {
                    "prior_state": {"values": {"root_module": {"resources": []}}},
                    "planned_values": {"root_module": {"resources": []}},
                    "resource_changes": [],
                    "checks": [inventory_check()],
                },
                "{",
            ),
            "unsafe-redaction": (
                {
                    "prior_state": {
                        "values": {
                            "root_module": {
                                "resources": [
                                    {
                                        "address": f'github_repository.repo["{unsafe_name}"]',
                                        "mode": "managed",
                                        "type": "github_repository",
                                        "name": "repo",
                                        "index": unsafe_name,
                                        "values": {
                                            "name": unsafe_name,
                                            "visibility": "unclassifiable",
                                        },
                                    }
                                ]
                            }
                        }
                    },
                    "planned_values": {"root_module": {"resources": []}},
                    "resource_changes": [],
                    "checks": [inventory_check()],
                },
                json.dumps(results),
            ),
        }
        for label, (plan, results_text) in cases.items():
            with self.subTest(case=label), tempfile.TemporaryDirectory() as raw_tmp:
                root = Path(raw_tmp)
                tmp = self.stage_provider_gap_tool(root)
                (tmp / "plan.json").write_text(json.dumps(plan), encoding="utf-8")
                (tmp / "provider-gap-desired-state.json").write_text(
                    json.dumps(desired), encoding="utf-8"
                )
                (tmp / "provider-gap-results.json").write_text(
                    results_text, encoding="utf-8"
                )
                (tmp / "inventory-metadata.status").write_text("skipped\n", encoding="utf-8")
                (tmp / "inventory-metadata.json").write_text("", encoding="utf-8")
                gh_log = tmp / "gh.jsonl"
                gh_stub = tmp / "gh_stub.py"
                gh_stub.write_text(
                    "import os, sys\n"
                    "with open(os.environ['GH_LOG'], 'a', encoding='utf-8') as fh:\n"
                    "    fh.write('called\\n')\n",
                    encoding="utf-8",
                )
                env = os.environ.copy()
                env.update(
                    {
                        "GH_LOG": str(gh_log),
                        "GH_STUB": str(gh_stub),
                        "EXISTING_ISSUE": "42",
                        "GH_TOKEN": "stub-token",
                        "REPO": "example/caller",
                        "RUN_URL": "https://example.invalid/actions/runs/1",
                        "TF_VAR_github_is_organization": "false",
                        "TF_VAR_github_owner": INVENTORY_OWNER,
                        "TF_VAR_github_token": TOKEN_SENTINEL,
                        "DETECTOR_MODE": "true",
                        "GITHUB_STEP_SUMMARY": str(tmp / "summary.md"),
                    }
                )
                summary_proc = subprocess.run(
                    ["bash", "-c", self.summary],
                    cwd=tmp,
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(summary_proc.returncode, 0)
                wrapped = f'''gh() {{ "{sys.executable}" "$GH_STUB" "$@"; }}
{self.reporter}'''
                proc = subprocess.run(
                    ["bash", "-c", wrapped],
                    cwd=tmp,
                    env=env,
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(proc.returncode, 0)
                self.assertFalse(gh_log.exists(), "unsafe reporter must stop before issue lifecycle")
                surfaces = (
                    summary_proc.stdout
                    + summary_proc.stderr
                    + proc.stdout
                    + proc.stderr
                )
                self.assertNotIn(unsafe_name, surfaces)
                self.assertNotIn("issue close", surfaces)

    def test_provider_gap_workflow_wrapper_and_cleanup_are_closed(self):
        verifier = step_run("Verify provider gaps")
        self.assertIn("set +e", verifier)
        self.assertIn("verifier_status=$?", verifier)
        self.assertIn("set -e", verifier)
        self.assertEqual(verifier.count("$GITHUB_OUTPUT"), 1)
        self.assertIn('echo "exit_code=${verifier_status}"', verifier)
        self.assertNotIn("TF_VAR_github_token", verifier)
        extraction = step_run("Extract provider-gap desired state")
        self.assertIn(".planned_values.outputs.provider_gap_desired_state.value", extraction)
        self.assertNotIn("// {}", extraction)
        cleanup = step_run("Cleanup workspace")
        self.assertIn("provider-gap-desired-state.json", cleanup)
        self.assertIn("provider-gap-results.json", cleanup)


class ETagEvidenceTests(unittest.TestCase):
    """Exercise conditional reads through the exact pinned provider and CLI."""

    def test_exact_toolchain_and_all_four_affected_declared_types(self):
        versions = VERSIONS.read_text(encoding="utf-8")
        self.assertRegex(versions, r'required_version\s*=\s*"= 1\.15\.4"')
        self.assertRegex(versions, r'version\s*=\s*"= 6\.12\.1"')
        self.assertIn('terraform_version: "1.15.4"', WORKFLOW_TEXT)

        terraform_version = subprocess.run(
            ["terraform", "version", "-json"], cwd=ROOT,
            check=True, capture_output=True, text=True
        )
        self.assertEqual(json.loads(terraform_version.stdout)["terraform_version"], "1.15.4")

        installed = (
            ROOT / "terraform" / ".terraform" / "providers" / "registry.terraform.io"
            / "integrations" / "github" / "6.12.1" / "linux_amd64"
        )
        self.assertTrue(installed.is_dir(), "run `make init` before the test suite")
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            (tmp / "versions.tf").write_text(
                """terraform {
  required_version = "= 1.15.4"
  required_providers {
    github = {
      source  = "integrations/github"
      version = "= 6.12.1"
    }
  }
}
""",
                encoding="utf-8",
            )
            shutil.copyfile(
                ROOT / "terraform" / ".terraform.lock.hcl", tmp / ".terraform.lock.hcl"
            )
            init_proc = subprocess.run(
                [
                    "terraform", "init", "-backend=false", "-input=false",
                    f"-plugin-dir={ROOT / 'terraform' / '.terraform' / 'providers'}",
                ],
                cwd=tmp, capture_output=True, text=True,
            )
            self.assertEqual(init_proc.returncode, 0, init_proc.stdout + init_proc.stderr)
            schema_proc = subprocess.run(
                ["terraform", "providers", "schema", "-json"], cwd=tmp,
                check=True, capture_output=True, text=True
            )
        schemas = json.loads(schema_proc.stdout)["provider_schemas"]
        provider = schemas["registry.terraform.io/integrations/github"]
        resources = provider["resource_schemas"]
        declared = RESOURCES.read_text(encoding="utf-8")
        affected = {
            "github_branch",
            "github_branch_default",
            "github_repository",
            "github_repository_ruleset",
        }
        for resource_type in affected:
            with self.subTest(resource_type=resource_type):
                self.assertIn(f'resource "{resource_type}"', declared)
                etag = resources[resource_type]["block"]["attributes"]["etag"]
                self.assertTrue(etag["computed"])

        # The response proof exercises both ETag schema flavors.
        self.assertTrue(resources["github_repository"]["block"]["attributes"]["etag"]["optional"])
        self.assertTrue(
            resources["github_branch_default"]["block"]["attributes"]["etag"]["optional"]
        )
        self.assertFalse(
            resources["github_repository_ruleset"]["block"]["attributes"]["etag"].get(
                "optional", False
            )
        )

    def test_pinned_provider_returns_304_then_200_and_exposes_false_clean(self):
        records: list[tuple[str, str, int]] = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
                path = self.path.split("?", 1)[0]
                endpoints = {
                    "/api/v3/repos/FixtureOwner/repository-fixture": (
                        "github_repository.target",
                        "github_repository",
                        {
                            "id": 1,
                            "node_id": "R_fixture",
                            "name": "repository-fixture",
                            "full_name": "FixtureOwner/repository-fixture",
                            "description": "live-description",
                            "private": False,
                            "visibility": "public",
                            "fork": False,
                            "archived": False,
                            "default_branch": "main",
                            "topics": [],
                        },
                    ),
                    "/api/v3/repos/FixtureOwner/fixture": (
                        "github_branch_default.target",
                        "github_branch_default",
                        {"name": "fixture", "default_branch": "live-branch"},
                    ),
                    "/api/v3/repos/FixtureOwner/fixture/rulesets/123": (
                        "github_repository_ruleset.target",
                        "github_repository_ruleset",
                        {
                            "id": 123,
                            "name": "Fixture Rules",
                            "target": "branch",
                            "source_type": "Repository",
                            "source": "FixtureOwner/fixture",
                            "enforcement": "active",
                            "conditions": {
                                "ref_name": {
                                    "include": ["~DEFAULT_BRANCH"],
                                    "exclude": [],
                                }
                            },
                            "rules": [{"type": "creation"}],
                            "bypass_actors": [],
                            "node_id": "RRS_fixture",
                        },
                    ),
                }
                endpoint = endpoints.get(path)
                if path.startswith(
                    "/api/v3/repos/FixtureOwner/branch-fixture/git/ref/"
                ):
                    endpoint = (
                        "github_branch.target",
                        "github_branch",
                        {
                            "ref": "refs/heads/main",
                            "node_id": "REF_fixture",
                            "url": f"http://{self.server.server_address[0]}/ref",
                            "object": {
                                "sha": "0123456789abcdef0123456789abcdef01234567",
                                "type": "commit",
                                "url": f"http://{self.server.server_address[0]}/commit",
                            },
                        },
                    )
                if endpoint is None:
                    self.send_error(404)
                    return
                address, resource_type, payload = endpoint
                # Model an ordinary HTTP conditional endpoint. The regression
                # assertions below consume only the resulting response status.
                conditional = any(
                    name.lower() == "if-none-match" for name in self.headers.keys()
                )
                status = 304 if conditional else 200
                records.append((address, resource_type, status))
                self.send_response(status)
                self.send_header("ETag", 'W/"fixture-etag"')
                if status == 200:
                    body = json.dumps(payload).encode()
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if status == 200:
                    self.wfile.write(body)

            def log_message(self, _format, *_args):
                return

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base_url = f"http://127.0.0.1:{server.server_port}/"

        state = {
            "version": 4,
            "terraform_version": "1.15.4",
            "serial": 1,
            "lineage": "00000000-0000-0000-0000-000000000001",
            "outputs": {},
            "resources": [
                {
                    "mode": "managed",
                    "type": "github_repository",
                    "name": "target",
                    "provider": 'provider["registry.terraform.io/integrations/github"]',
                    "instances": [
                        {
                            "schema_version": 0,
                            "attributes": {
                                "description": "desired-description",
                                "etag": 'W/"fixture-etag"',
                                "id": "repository-fixture",
                                "name": "repository-fixture",
                            },
                            "sensitive_attributes": [],
                        }
                    ],
                },
                {
                    "mode": "managed",
                    "type": "github_branch",
                    "name": "target",
                    "provider": 'provider["registry.terraform.io/integrations/github"]',
                    "instances": [
                        {
                            "schema_version": 0,
                            "attributes": {
                                "branch": "main",
                                "etag": 'W/"fixture-etag"',
                                "id": "branch-fixture:main",
                                "ref": "refs/heads/main",
                                "repository": "branch-fixture",
                                "sha": "0123456789abcdef0123456789abcdef01234567",
                                "source_branch": "main",
                                "source_sha": None,
                            },
                            "sensitive_attributes": [],
                        }
                    ],
                },
                {
                    "mode": "managed",
                    "type": "github_branch_default",
                    "name": "target",
                    "provider": 'provider["registry.terraform.io/integrations/github"]',
                    "instances": [
                        {
                            "schema_version": 0,
                            "attributes": {
                                "branch": "desired-branch",
                                "etag": 'W/"fixture-etag"',
                                "id": "fixture",
                                "rename": False,
                                "repository": "fixture",
                            },
                            "sensitive_attributes": [],
                        }
                    ],
                },
                {
                    "mode": "managed",
                    "type": "github_repository_ruleset",
                    "name": "target",
                    "provider": 'provider["registry.terraform.io/integrations/github"]',
                    "instances": [
                        {
                            "schema_version": 0,
                            "attributes": {
                                "bypass_actors": [],
                                "conditions": [
                                    {
                                        "ref_name": [
                                            {
                                                "exclude": [],
                                                "include": ["~DEFAULT_BRANCH"],
                                            }
                                        ]
                                    }
                                ],
                                "enforcement": "active",
                                "etag": 'W/"fixture-etag"',
                                "id": "123",
                                "name": "Fixture Rules",
                                "node_id": "RRS_fixture",
                                "repository": "fixture",
                                "rules": [{"creation": True}],
                                "ruleset_id": 123,
                                "target": "branch",
                            },
                            "sensitive_attributes": [],
                        }
                    ],
                },
            ],
            "check_results": None,
        }

        def configuration() -> str:
            return f'''terraform {{
  required_version = "= 1.15.4"
  required_providers {{
    github = {{
      source  = "integrations/github"
      version = "= 6.12.1"
    }}
  }}
}}

provider "github" {{
  owner    = "FixtureOwner"
  token    = "fixture-token"
  base_url = "{base_url}"
  insecure = true
}}

resource "github_branch_default" "target" {{
  repository = "fixture"
  branch     = "desired-branch"
  rename     = false
}}

resource "github_repository" "target" {{
  name        = "repository-fixture"
  description = "desired-description"
}}

resource "github_branch" "target" {{
  repository    = "branch-fixture"
  branch        = "main"
  source_branch = "main"
}}

resource "github_repository_ruleset" "target" {{
  repository  = "fixture"
  name        = "Fixture Rules"
  target      = "branch"
  enforcement = "active"
  conditions {{
    ref_name {{
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }}
  }}
  rules {{
    creation = true
  }}
}}
'''

        installed_plugins = ROOT / "terraform" / ".terraform" / "providers"
        provider_binary = (
            installed_plugins / "registry.terraform.io" / "integrations" / "github"
            / "6.12.1" / "linux_amd64"
        )
        self.assertTrue(provider_binary.is_dir(), "run `make init` before the test suite")

        def prepare(module: Path, state_name: str, state_payload: dict) -> None:
            module.mkdir()
            (module / "main.tf").write_text(configuration(), encoding="utf-8")
            shutil.copyfile(
                ROOT / "terraform" / ".terraform.lock.hcl", module / ".terraform.lock.hcl"
            )
            proc = subprocess.run(
                [
                    "terraform", "init", "-input=false",
                    f"-plugin-dir={installed_plugins}",
                ],
                cwd=module, capture_output=True, text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            (module / state_name).write_text(json.dumps(state_payload), encoding="utf-8")
            listed = subprocess.run(
                ["terraform", "state", "list"], cwd=module,
                capture_output=True, text=True,
            )
            self.assertEqual(listed.returncode, 0, listed.stdout + listed.stderr)
            self.assertIn("github_branch_default.target", listed.stdout)

        def plan(module: Path, name: str) -> dict:
            env = os.environ.copy()
            for key in ("GITHUB_OWNER", "GITHUB_ORGANIZATION", "GITHUB_BASE_URL"):
                env.pop(key, None)
            env.update({"TF_LOG": "DEBUG", "TF_LOG_PATH": str(module / f"{name}.log")})
            proc = subprocess.run(
                [
                    "terraform", "plan", "-input=false", "-lock=false", "-no-color",
                    f"-out={name}.tfplan",
                ],
                cwd=module, env=env, capture_output=True, text=True,
            )
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            shown = subprocess.run(
                ["terraform", "show", "-json", f"{name}.tfplan"],
                cwd=module, check=True, capture_output=True, text=True,
            )
            return json.loads(shown.stdout)

        try:
            with tempfile.TemporaryDirectory() as raw_tmp:
                tmp = Path(raw_tmp)
                baseline_module = tmp / "baseline"
                detector_module = tmp / "detector"
                prepare(baseline_module, "terraform.tfstate", state)

                detector_module.mkdir()
                (detector_module / "main.tf").write_text(
                    configuration(), encoding="utf-8"
                )
                shutil.copyfile(
                    ROOT / "terraform" / ".terraform.lock.hcl",
                    detector_module / ".terraform.lock.hcl",
                )
                canonical = detector_module / "canonical.tfstate"
                canonical.write_text(json.dumps(state), encoding="utf-8")
                strip = re.search(
                    r"jq '([^']+)' \\\n+\s+canonical\.tfstate > stripped\.tfstate",
                    step_run("Terraform init (ETag-stripped local backend)"),
                )
                self.assertIsNotNone(strip, "shipped ETag strip command is missing")
                stripped = subprocess.run(
                    ["jq", strip.group(1), str(canonical)],
                    check=True, capture_output=True,
                )
                canonical.unlink()
                init = subprocess.run(
                    [
                        "terraform", "init", "-input=false",
                        f"-plugin-dir={installed_plugins}",
                    ],
                    cwd=detector_module, capture_output=True, text=True,
                )
                self.assertEqual(init.returncode, 0, init.stdout + init.stderr)
                (detector_module / "terraform.tfstate").write_bytes(stripped.stdout)

                baseline_plan = plan(baseline_module, "baseline")
                self.assertTrue(
                    records,
                    (baseline_module / "baseline.log").read_text(encoding="utf-8")[-12000:],
                )
                detector_plan = plan(detector_module, "detector")

                self.assertCountEqual(
                    records,
                    [
                        ("github_repository.target", "github_repository", 304),
                        ("github_branch.target", "github_branch", 304),
                        ("github_repository_ruleset.target", "github_repository_ruleset", 304),
                        ("github_branch_default.target", "github_branch_default", 304),
                        ("github_repository.target", "github_repository", 200),
                        ("github_branch.target", "github_branch", 200),
                        ("github_repository_ruleset.target", "github_repository_ruleset", 200),
                        ("github_branch_default.target", "github_branch_default", 200),
                    ],
                )
                for module, name, status in (
                    (baseline_module, "baseline", 304),
                    (detector_module, "detector", 200),
                ):
                    log = (module / f"{name}.log").read_text(encoding="utf-8")
                    response_blocks = []
                    for response in re.finditer(r"Received HTTP Response:", log):
                        following = log[response.end():]
                        boundary = re.search(
                            r"(?:Sending HTTP Request:|Received HTTP Response:)", following
                        )
                        response_blocks.append(
                            following[:boundary.start()] if boundary else following
                        )
                    # The legacy branch Read functions do not attach a resource
                    # type to their HTTP logging context. Their named endpoint/status
                    # correlation is asserted through the server records above.
                    for resource_type in (
                        "github_repository", "github_repository_ruleset"
                    ):
                        matching_responses = [
                            block for block in response_blocks
                            if f"tf_resource_type={resource_type}" in block
                            and f"tf_http_res_status_code={status}" in block
                        ]
                        self.assertTrue(
                            matching_responses,
                            f"missing {status} response for {resource_type}",
                        )

                def actions(plan_json: dict, address: str) -> list[str]:
                    row = next(
                        item for item in plan_json["resource_changes"]
                        if item["address"] == address
                    )
                    return row["change"]["actions"]

                address = "github_branch_default.target"
                self.assertEqual(actions(baseline_plan, address), ["no-op"])
                self.assertEqual(actions(detector_plan, address), ["update"])
        finally:
            server.shutdown()
            thread.join()
            server.server_close()

    def test_stripping_is_action_neutral_but_not_refresh_drift_neutral(self):
        action_set = [
            ("github_repository.repo[\"fixture\"]", ("update",)),
            ("github_repository_ruleset.branch[\"fixture-rules\"]", ("no-op",)),
        ]
        baseline_resource_changes = action_set
        stripped_resource_changes = list(action_set)
        stripped_resource_drift = [
            (address, ("update",), None, 'W/"refreshed"')
            for address, _ in action_set
        ]
        self.assertEqual(baseline_resource_changes, stripped_resource_changes)
        self.assertEqual(len(stripped_resource_drift), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
