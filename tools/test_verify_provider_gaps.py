#!/usr/bin/env python3
"""Contract and integration tests for the shipped provider-gap implementation."""

from __future__ import annotations

import contextlib
import http.client
import http.server
import io
import json
import os
import re
import signal
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

import verify_provider_gaps as gaps


OWNER = "FixtureOwner"
POLICY = "all_external_contributors"
OTHER_POLICY = "first_time_contributors"
TOKEN = "credential-sentinel-provider-gap"
PRIVATE_NAME = "private-timeout-sentinel"


def repository(
    name: str,
    *,
    visibility: str = "public",
    policy: str | None = POLICY,
    archived: bool = False,
) -> dict:
    return {
        "name": name,
        "visibility": visibility,
        "archived": archived,
        "provider_gaps": (
            None
            if policy is None
            else {"fork_pr_contributor_approval": policy}
        ),
    }


def projection(
    *,
    organization: bool = False,
    organization_policy: str | None = None,
    repositories: dict[str, dict] | None = None,
) -> dict:
    organization_gaps = None
    if organization_policy is not None:
        organization_gaps = {
            "fork_pr_contributor_approval": organization_policy,
            "code_security_configuration": None,
        }
    return {
        "schema_version": 1,
        "github_owner": OWNER,
        "github_is_organization": organization,
        "organization_provider_gaps": organization_gaps,
        "repositories": repositories if repositories is not None else {
            "fixture": repository("fixture")
        },
    }


def response(status: int, body: object | bytes) -> gaps.HttpResponse:
    encoded = body if isinstance(body, bytes) else json.dumps(body).encode()
    return gaps.HttpResponse(status, encoded)


class FakeClient:
    def __init__(self, responses: list[gaps.HttpResponse | Exception]):
        self.responses = list(responses)
        self.paths: list[str] = []

    def get(self, path: str) -> gaps.HttpResponse:
        self.paths.append(path)
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def exact_row(
    *,
    kind: str = "repository",
    target: str = f"{OWNER}/fixture",
    classification: str,
    declared: str | None = POLICY,
    live: str | None = None,
    reason: str,
) -> dict:
    return {
        "target_kind": kind,
        "target": target,
        "field": "fork_pr_contributor_approval",
        "classification": classification,
        "declared_policy": declared,
        "live_policy": live,
        "reason": reason,
    }


def managed_repository_row(
    name: str,
    visibility: str,
    *,
    address: str | None = None,
    index: str | None = None,
) -> dict:
    return {
        "address": address or f'github_repository.repo["{name}"]',
        "mode": "managed",
        "type": "github_repository",
        "name": "repo",
        "index": name if index is None else index,
        "values": {"name": name, "visibility": visibility},
    }


def inventory_data(name: str, names: list[str]) -> dict:
    return {
        "address": f'data.github_repositories.{name}["{OWNER}"]',
        "mode": "data",
        "type": "github_repositories",
        "name": name,
        "index": OWNER,
        "values": {"names": names},
    }


def inventory_check(status: str = "pass", message: str | None = None) -> dict:
    instance = {
        "address": {"to_display": gaps.INVENTORY_ADDRESS},
        "status": status,
    }
    if status == "fail":
        instance["problems"] = [{"message": message or "undeclared-public"}]
    return {
        "address": {
            "kind": "check",
            "name": "inventory_complete",
            "to_display": gaps.INVENTORY_ADDRESS,
        },
        "status": status,
        "instances": [instance],
    }


def plan_document(
    *,
    changes: list[dict] | None = None,
    prior_resources: list[dict] | None = None,
    planned_resources: list[dict] | None = None,
    checks: list[dict] | None = None,
) -> dict:
    return {
        "prior_state": {
            "values": {"root_module": {"resources": prior_resources or []}}
        },
        "planned_values": {"root_module": {"resources": planned_resources or []}},
        "resource_changes": changes or [],
        "checks": checks if checks is not None else [inventory_check()],
    }


def change(
    address: str,
    actions: list[str],
    *,
    resource_type: str = "github_repository_file",
    index: str | None = None,
    before: dict | None = None,
    after: dict | None = None,
) -> dict:
    row = {
        "address": address,
        "mode": "managed",
        "type": resource_type,
        "name": "repo",
        "change": {"actions": actions, "before": before, "after": after},
    }
    if index is not None:
        row["index"] = index
    return row


def run_raw_http_response(
    chunks: list[bytes],
    *,
    timeout: float,
    delay: float,
    value: dict | None = None,
) -> tuple[dict, int, int, float]:
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    listener.settimeout(2.0)
    requests = 0

    def serve() -> None:
        nonlocal requests
        try:
            connection, _ = listener.accept()
            with connection:
                request = bytearray()
                while b"\r\n\r\n" not in request:
                    part = connection.recv(4096)
                    if not part:
                        return
                    request.extend(part)
                requests += 1
                for chunk in chunks:
                    try:
                        connection.sendall(chunk)
                    except OSError:
                        return
                    time.sleep(delay)
        finally:
            listener.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    port = listener.getsockname()[1]

    def factory(_host: str, connection_timeout: float) -> http.client.HTTPConnection:
        return http.client.HTTPConnection("127.0.0.1", port, timeout=connection_timeout)

    started = time.monotonic()
    client = gaps.GitHubClient(TOKEN, timeout=timeout, connection_factory=factory)
    document, status = gaps.verify_projection(
        projection() if value is None else value,
        token=TOKEN,
        client=client,
    )
    elapsed = time.monotonic() - started
    thread.join(timeout=2.0)
    if thread.is_alive():
        raise AssertionError("raw HTTP peer did not stop")
    return document, status, requests, elapsed


class ContractLiteralTests(unittest.TestCase):
    def test_production_contract_literals_are_pinned_independently(self):
        self.assertEqual(
            gaps.PRIVATE_422_ERROR,
            "Fork PR approval is not allowed for private repositories.",
        )
        self.assertEqual(gaps.API_VERSION, "2026-03-10")
        self.assertEqual(gaps.PRIVATE_REPOSITORY_REDACTED, "<private-repository-redacted>")
        self.assertEqual(gaps.PRIVATE_RESOURCE_REDACTED, "<private-resource-redacted>")
        self.assertEqual(gaps.REQUEST_TIMEOUT_SECONDS, 30.0)


class ProjectionContractTests(unittest.TestCase):
    def assert_invalid(self, value: object) -> None:
        client = FakeClient([response(200, {"approval_policy": POLICY})])
        document, status = gaps.verify_projection(value, token=TOKEN, client=client)
        self.assertEqual(status, 1)
        self.assertEqual(client.paths, [])
        self.assertEqual(
            document,
            {
                "schema_version": 1,
                "counts": {
                    "MATCH": 0,
                    "DRIFT": 0,
                    "NOT-APPLICABLE": 0,
                    "INDETERMINATE": 0,
                    "DECLARATION-ERROR": 1,
                },
                "results": [
                    {
                        "target_kind": "projection",
                        "target": "provider_gap_desired_state",
                        "field": "provider_gap_desired_state",
                        "classification": "DECLARATION-ERROR",
                        "declared_policy": None,
                        "live_policy": None,
                        "reason": "invalid-desired-state-projection",
                    }
                ],
            },
        )

    def test_missing_null_unknown_wrong_types_and_boolean_schema_are_one_projection_error(self):
        valid = projection()
        cases: dict[str, object] = {
            "null": None,
            "missing-top-member": {k: v for k, v in valid.items() if k != "repositories"},
            "unknown-top-member": {**valid, "extra": None},
            "boolean-schema": {**valid, "schema_version": True},
            "empty-owner": {**valid, "github_owner": ""},
            "wrong-owner-kind": {**valid, "github_is_organization": 1},
            "repositories-null": {**valid, "repositories": None},
            "wrong-archived": projection(
                repositories={"fixture": {**repository("fixture"), "archived": 0}}
            ),
            "wrong-visibility": projection(
                repositories={"fixture": {**repository("fixture"), "visibility": "secret"}}
            ),
            "null-repository-policy-object": projection(
                repositories={
                    "fixture": {
                        **repository("fixture"),
                        "provider_gaps": {"fork_pr_contributor_approval": None},
                    }
                }
            ),
            "personal-org-policy": projection(
                organization=False,
                organization_policy=POLICY,
            ),
        }
        for label, value in cases.items():
            with self.subTest(case=label):
                self.assert_invalid(value)

    def test_duplicate_members_and_ascii_case_collisions_are_rejected_before_get(self):
        duplicate = (
            '{"schema_version":1,"schema_version":1,"github_owner":"FixtureOwner",'
            '"github_is_organization":false,"organization_provider_gaps":null,'
            '"repositories":{}}'
        )
        document, status = gaps.verify_text(duplicate, token=TOKEN, client=FakeClient([]))
        self.assertEqual(status, 1)
        self.assertEqual(document["results"], [gaps.invalid_projection_result()])

        nonstandard_number = duplicate.replace(
            '"schema_version":1,"schema_version":1', '"schema_version":NaN'
        )
        document, status = gaps.verify_text(
            nonstandard_number, token=TOKEN, client=FakeClient([])
        )
        self.assertEqual(status, 1)
        self.assertEqual(document["results"], [gaps.invalid_projection_result()])

        self.assert_invalid(
            projection(
                repositories={
                    "Repo": repository("Repo"),
                    "repo": repository("repo"),
                }
            )
        )

    def test_invalid_owner_repository_and_dot_segments_are_rejected_before_get(self):
        cases = {
            "owner": {**projection(), "github_owner": "bad/owner"},
            "slash": projection(repositories={"bad/name": repository("bad/name")}),
            "dot": projection(repositories={".": repository(".")}),
            "dotdot": projection(repositories={"..": repository("..")}),
            "too-long": projection(
                repositories={"r" * 101: repository("r" * 101)}
            ),
        }
        for label, value in cases.items():
            with self.subTest(case=label):
                self.assert_invalid(value)

    def test_organization_code_security_object_is_closed_and_typed(self):
        base = projection(organization=True, organization_policy=POLICY)
        good = json.loads(json.dumps(base))
        good["organization_provider_gaps"]["code_security_configuration"] = {
            "id": 7,
            "enforcement": "enforced",
            "defaults": ["dependency_graph"],
            "status": "configured",
        }
        gaps.validate_desired_state(good)
        for label, security in {
            "boolean-id": {"id": True, "enforcement": "x", "defaults": [], "status": "x"},
            "non-string-default": {"id": 1, "enforcement": "x", "defaults": [1], "status": "x"},
            "extra": {"id": 1, "enforcement": "x", "defaults": [], "status": "x", "extra": 1},
        }.items():
            with self.subTest(case=label):
                value = json.loads(json.dumps(base))
                value["organization_provider_gaps"]["code_security_configuration"] = security
                self.assert_invalid(value)


class DeclarationAndClassifierTests(unittest.TestCase):
    def test_exact_target_order_organization_inheritance_and_override(self):
        value = projection(
            organization=True,
            organization_policy=POLICY,
            repositories={
                "zeta": repository("zeta", policy=None),
                "Alpha": repository("Alpha", policy=OTHER_POLICY),
                "private": repository("private", visibility="private", policy=None),
            },
        )
        client = FakeClient(
            [
                response(200, {"approval_policy": POLICY}),
                response(200, {"approval_policy": OTHER_POLICY}),
                response(422, {"errors": gaps.PRIVATE_422_ERROR}),
                response(200, {"approval_policy": POLICY}),
            ]
        )
        document, status = gaps.verify_projection(value, token=TOKEN, client=client)
        self.assertEqual(status, 0)
        self.assertEqual(
            client.paths,
            [
                "/orgs/FixtureOwner/actions/permissions/fork-pr-contributor-approval",
                "/repos/FixtureOwner/Alpha/actions/permissions/fork-pr-contributor-approval",
                "/repos/FixtureOwner/private/actions/permissions/fork-pr-contributor-approval",
                "/repos/FixtureOwner/zeta/actions/permissions/fork-pr-contributor-approval",
            ],
        )
        self.assertEqual(
            [row["declared_policy"] for row in document["results"]],
            [POLICY, OTHER_POLICY, None, POLICY],
        )
        self.assertEqual(
            [row["classification"] for row in document["results"]],
            ["MATCH", "MATCH", "NOT-APPLICABLE", "MATCH"],
        )

    def test_declaration_errors_precede_missing_credential_and_network(self):
        value = projection(
            repositories={
                "missing": repository("missing", policy=None),
                "private": repository("private", visibility="private", policy=POLICY),
                "requestable": repository("requestable", policy=POLICY),
            }
        )
        client = FakeClient([])
        document, status = gaps.verify_projection(value, token="", client=client)
        self.assertEqual(status, 1)
        self.assertEqual(client.paths, [])
        self.assertEqual(
            document["results"],
            [
                exact_row(
                    target=f"{OWNER}/missing",
                    classification="DECLARATION-ERROR",
                    declared=None,
                    reason="declaration-missing",
                ),
                exact_row(
                    target=f"{OWNER}/private",
                    classification="DECLARATION-ERROR",
                    declared=POLICY,
                    reason="private-declaration-forbidden",
                ),
                exact_row(
                    target=f"{OWNER}/requestable",
                    classification="INDETERMINATE",
                    declared=POLICY,
                    reason="credential-missing",
                ),
            ],
        )

    def test_private_422_matrix_uses_only_exact_conjunction(self):
        real = {
            "message": "Validation Failed",
            "errors": gaps.PRIVATE_422_ERROR,
            "documentation_url": "https://docs.github.com/rest/actions/permissions",
            "status": "422",
        }
        cases: dict[str, tuple[bytes | object, str, str]] = {
            "real-with-string-body-status": (real, "NOT-APPLICABLE", "private-repository"),
            "different-punctuation": ({"errors": gaps.PRIVATE_422_ERROR[:-1]}, "INDETERMINATE", "private-422-contract-mismatch"),
            "errors-array": ({"errors": [gaps.PRIVATE_422_ERROR]}, "INDETERMINATE", "private-422-contract-mismatch"),
            "malformed-json": (b"{", "INDETERMINATE", "private-422-contract-mismatch"),
            "non-object": ([], "INDETERMINATE", "private-422-contract-mismatch"),
            "missing-errors": ({"status": "422"}, "INDETERMINATE", "private-422-contract-mismatch"),
            "nonmatching-422": ({"errors": "Validation Failed"}, "INDETERMINATE", "private-422-contract-mismatch"),
        }
        value = projection(
            repositories={"private": repository("private", visibility="private", policy=None)}
        )
        for label, (body, classification, reason) in cases.items():
            with self.subTest(case=label):
                client = FakeClient([response(422, body)])
                document, status = gaps.verify_projection(value, token=TOKEN, client=client)
                self.assertEqual(len(client.paths), 1)
                self.assertEqual(
                    document["results"],
                    [
                        exact_row(
                            target=f"{OWNER}/private",
                            classification=classification,
                            declared=None,
                            reason=reason,
                        )
                    ],
                )
                self.assertEqual(status, int(classification == "INDETERMINATE"))

    def test_personal_target_set_has_repositories_only_and_missing_declaration(self):
        value = projection(
            repositories={
                "Alpha": repository("Alpha", policy=POLICY),
                "zeta": repository("zeta", policy=None),
            }
        )
        client = FakeClient([response(200, {"approval_policy": POLICY})])
        document, status = gaps.verify_projection(value, token=TOKEN, client=client)
        self.assertEqual(status, 1)
        self.assertEqual(
            client.paths,
            ["/repos/FixtureOwner/Alpha/actions/permissions/fork-pr-contributor-approval"],
        )
        self.assertEqual(
            [row["target"] for row in document["results"]],
            [f"{OWNER}/Alpha", f"{OWNER}/zeta"],
        )
        self.assertEqual(document["results"][1]["reason"], "declaration-missing")

    def test_every_representative_non_200_status_is_http_indeterminate(self):
        statuses = (201, 204, 302, 400, 401, 403, 404, 405, 409, 418, 429, 500, 503)
        for status_code in statuses:
            with self.subTest(status=status_code):
                client = FakeClient([response(status_code, {"approval_policy": POLICY})])
                document, status = gaps.verify_projection(
                    projection(), token=TOKEN, client=client
                )
                self.assertEqual(status, 1)
                self.assertEqual(
                    document["results"],
                    [
                        exact_row(
                            classification="INDETERMINATE",
                            reason=f"http-{status_code}",
                        )
                    ],
                )

    def test_all_200_body_branches_and_legal_wrong_policy(self):
        cases: dict[str, tuple[bytes | object, str, str, str | None]] = {
            "malformed": (b"{", "INDETERMINATE", "malformed-json", None),
            "non-object": ([], "INDETERMINATE", "response-not-object", None),
            "missing": ({}, "INDETERMINATE", "approval-policy-missing", None),
            "not-string": ({"approval_policy": 7}, "INDETERMINATE", "approval-policy-not-string", None),
            "unknown": ({"approval_policy": "future-policy"}, "INDETERMINATE", "live-policy-unknown", None),
            "match": ({"approval_policy": POLICY}, "MATCH", "policy-match", POLICY),
            "legal-wrong": ({"approval_policy": POLICY}, "DRIFT", "policy-mismatch", POLICY),
        }
        for label, (body, classification, reason, live) in cases.items():
            with self.subTest(case=label):
                declared = OTHER_POLICY if label == "legal-wrong" else POLICY
                value = projection(repositories={"fixture": repository("fixture", policy=declared)})
                document, status = gaps.verify_projection(
                    value,
                    token=TOKEN,
                    client=FakeClient([response(200, body)]),
                )
                self.assertEqual(
                    document["results"],
                    [
                        exact_row(
                            classification=classification,
                            declared=declared,
                            live=live,
                            reason=reason,
                        )
                    ],
                )
                self.assertEqual(status, int(classification in gaps.ACTIONABLE_GAP_CLASSES))

    def test_archived_targets_compare_normally_on_200_and_404(self):
        value = projection(
            repositories={"fixture": repository("fixture", archived=True)}
        )
        document, status = gaps.verify_projection(
            value,
            token=TOKEN,
            client=FakeClient([response(200, {"approval_policy": POLICY})]),
        )
        self.assertEqual(status, 0)
        self.assertEqual(document["results"][0]["classification"], "MATCH")
        document, status = gaps.verify_projection(
            value,
            token=TOKEN,
            client=FakeClient([response(404, {})]),
        )
        self.assertEqual(status, 1)
        self.assertEqual(document["results"][0]["classification"], "INDETERMINATE")
        self.assertEqual(document["results"][0]["reason"], "http-404")

    def test_transport_failure_is_exact_and_nonzero(self):
        document, status = gaps.verify_projection(
            projection(),
            token=TOKEN,
            client=FakeClient([gaps.TransportFailure()]),
        )
        self.assertEqual(status, 1)
        self.assertEqual(
            document["results"],
            [exact_row(classification="INDETERMINATE", reason="transport-failure")],
        )

    def test_every_valid_http_status_obeys_the_closed_classifier_contract(self):
        applicable_projection = projection()
        applicable_target = gaps.desired_targets(applicable_projection)[0]
        private_projection = projection(
            repositories={
                "private": repository("private", visibility="private", policy=None)
            }
        )
        private_target = gaps.desired_targets(private_projection)[0]

        for status_code in range(100, 600):
            with self.subTest(target="applicable", status=status_code):
                row = gaps.classify_response(
                    applicable_target,
                    response(status_code, {"approval_policy": POLICY}),
                )
                if status_code == 200:
                    self.assertEqual((row["classification"], row["reason"]), ("MATCH", "policy-match"))
                else:
                    self.assertEqual(
                        (row["classification"], row["reason"]),
                        ("INDETERMINATE", f"http-{status_code}"),
                    )
                gaps.validate_results(gaps.result_document([row]), applicable_projection)

            with self.subTest(target="private", status=status_code):
                row = gaps.classify_response(
                    private_target,
                    response(
                        status_code,
                        {"errors": "Fork PR approval is not allowed for private repositories."},
                    ),
                )
                if status_code == 422:
                    self.assertEqual(
                        (row["classification"], row["reason"]),
                        ("NOT-APPLICABLE", "private-repository"),
                    )
                else:
                    self.assertEqual(
                        (row["classification"], row["reason"]),
                        ("INDETERMINATE", f"http-{status_code}"),
                    )
                gaps.validate_results(gaps.result_document([row]), private_projection)

    def test_non_http_branches_form_one_closed_row_contract(self):
        applicable_projection = projection()
        private_projection = projection(
            repositories={
                "private": repository("private", visibility="private", policy=None)
            }
        )
        cases = [
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="credential-missing"),
            ),
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="transport-failure"),
            ),
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="malformed-json"),
            ),
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="response-not-object"),
            ),
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="approval-policy-missing"),
            ),
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="approval-policy-not-string"),
            ),
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="live-policy-unknown"),
            ),
            (
                applicable_projection,
                exact_row(
                    classification="MATCH",
                    live=POLICY,
                    reason="policy-match",
                ),
            ),
            (
                projection(repositories={"fixture": repository("fixture", policy=OTHER_POLICY)}),
                exact_row(
                    classification="DRIFT",
                    declared=OTHER_POLICY,
                    live=POLICY,
                    reason="policy-mismatch",
                ),
            ),
            (
                private_projection,
                exact_row(
                    target=f"{OWNER}/private",
                    classification="INDETERMINATE",
                    declared=None,
                    reason="credential-missing",
                ),
            ),
            (
                private_projection,
                exact_row(
                    target=f"{OWNER}/private",
                    classification="INDETERMINATE",
                    declared=None,
                    reason="transport-failure",
                ),
            ),
            (
                private_projection,
                exact_row(
                    target=f"{OWNER}/private",
                    classification="INDETERMINATE",
                    declared=None,
                    reason="private-422-contract-mismatch",
                ),
            ),
            (
                private_projection,
                exact_row(
                    target=f"{OWNER}/private",
                    classification="NOT-APPLICABLE",
                    declared=None,
                    reason="private-repository",
                ),
            ),
            (
                projection(repositories={"missing": repository("missing", policy=None)}),
                exact_row(
                    target=f"{OWNER}/missing",
                    classification="DECLARATION-ERROR",
                    declared=None,
                    reason="declaration-missing",
                ),
            ),
            (
                projection(
                    repositories={
                        "private": repository("private", visibility="private", policy=POLICY)
                    }
                ),
                exact_row(
                    target=f"{OWNER}/private",
                    classification="DECLARATION-ERROR",
                    reason="private-declaration-forbidden",
                ),
            ),
        ]
        for case_projection, row in cases:
            with self.subTest(reason=row["reason"], target=row["target"]):
                gaps.validate_results(gaps.result_document([row]), case_projection)

        gaps.validate_results(gaps.result_document([gaps.invalid_projection_result()]))

    def test_impossible_http_reasons_and_mixed_credentials_are_rejected(self):
        applicable_projection = projection()
        private_projection = projection(
            repositories={
                "private": repository("private", visibility="private", policy=None)
            }
        )
        for status_code in (0, 99, 600, 999):
            for case_projection, target, declared in (
                (applicable_projection, f"{OWNER}/fixture", POLICY),
                (private_projection, f"{OWNER}/private", None),
            ):
                with self.subTest(status=status_code, target=target):
                    row = exact_row(
                        target=target,
                        classification="INDETERMINATE",
                        declared=declared,
                        reason=f"http-{status_code:03d}",
                    )
                    with self.assertRaises(gaps.ContractError):
                        gaps.validate_results(gaps.result_document([row]), case_projection)

        impossible = (
            (
                applicable_projection,
                exact_row(classification="INDETERMINATE", reason="http-200"),
            ),
            (
                private_projection,
                exact_row(
                    target=f"{OWNER}/private",
                    classification="INDETERMINATE",
                    declared=None,
                    reason="http-422",
                ),
            ),
        )
        for case_projection, row in impossible:
            with self.subTest(reason=row["reason"]):
                with self.assertRaises(gaps.ContractError):
                    gaps.validate_results(gaps.result_document([row]), case_projection)

        applicable_target = gaps.desired_targets(applicable_projection)[0]
        for invalid_status in (True, False, -1, 600, 999):
            with self.subTest(direct_status=invalid_status):
                row = gaps.classify_response(
                    applicable_target,
                    response(invalid_status, {"approval_policy": POLICY}),
                )
                self.assertEqual(
                    (row["classification"], row["reason"]),
                    ("INDETERMINATE", "transport-failure"),
                )
                gaps.validate_results(gaps.result_document([row]), applicable_projection)

        allowed_projection = projection(
            repositories={
                "missing": repository("missing", policy=None),
                "requestable": repository("requestable", policy=POLICY),
            }
        )
        gaps.validate_results(
            gaps.result_document(
                [
                    exact_row(
                        target=f"{OWNER}/missing",
                        classification="DECLARATION-ERROR",
                        declared=None,
                        reason="declaration-missing",
                    ),
                    exact_row(
                        target=f"{OWNER}/requestable",
                        classification="INDETERMINATE",
                        reason="credential-missing",
                    ),
                ]
            ),
            allowed_projection,
        )

        mixed_projection = projection(
            repositories={
                "alpha": repository("alpha"),
                "beta": repository("beta"),
            }
        )
        mixed = gaps.result_document(
            [
                exact_row(
                    target=f"{OWNER}/alpha",
                    classification="INDETERMINATE",
                    reason="credential-missing",
                ),
                exact_row(
                    target=f"{OWNER}/beta",
                    classification="INDETERMINATE",
                    reason="http-403",
                ),
            ]
        )
        with self.assertRaises(gaps.ContractError):
            gaps.validate_results(mixed, mixed_projection)


class ShippedHttpClientTests(unittest.TestCase):
    def run_server_case(self, location: str) -> tuple[dict, int, list[dict]]:
        requests: list[dict] = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802
                requests.append(
                    {
                        "method": self.command,
                        "path": self.path,
                        "authorization": self.headers.get("Authorization"),
                        "accept": self.headers.get("Accept"),
                        "user_agent": self.headers.get("User-Agent"),
                        "version": self.headers.get("X-GitHub-Api-Version"),
                    }
                )
                self.send_response(302)
                self.send_header("Location", location)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, _format, *_args):
                return

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def factory(_host: str, timeout: float) -> http.client.HTTPConnection:
            return http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=timeout)

        try:
            client = gaps.GitHubClient(TOKEN, timeout=1.0, connection_factory=factory)
            document, status = gaps.verify_projection(projection(), token=TOKEN, client=client)
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        return document, status, requests

    def test_same_and_cross_origin_redirects_are_one_get_with_no_follow(self):
        for location in (
            "/second-request-must-not-happen",
            "https://example.invalid/credential-must-not-be-forwarded",
        ):
            with self.subTest(location=location):
                document, status, requests = self.run_server_case(location)
                self.assertEqual(status, 1)
                self.assertEqual(len(requests), 1)
                self.assertEqual(requests[0]["method"], "GET")
                self.assertEqual(
                    requests[0]["path"],
                    "/repos/FixtureOwner/fixture/actions/permissions/fork-pr-contributor-approval",
                )
                self.assertEqual(requests[0]["authorization"], f"Bearer {TOKEN}")
                self.assertEqual(requests[0]["accept"], "application/vnd.github+json")
                self.assertEqual(
                    requests[0]["user_agent"],
                    "github-terraform-framework-provider-gap-verifier/1",
                )
                self.assertEqual(requests[0]["version"], gaps.API_VERSION)
                self.assertEqual(document["results"][0]["reason"], "http-302")
                self.assertNotIn(TOKEN, json.dumps(document))

    def test_cross_origin_redirect_forwards_no_request_or_authorization(self):
        destination_requests: list[str | None] = []

        class Destination(http.server.BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802
                destination_requests.append(self.headers.get("Authorization"))
                self.send_response(200)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def log_message(self, _format, *_args):
                return

        destination = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Destination)
        thread = threading.Thread(target=destination.serve_forever, daemon=True)
        thread.start()
        try:
            location = f"http://127.0.0.1:{destination.server_port}/must-not-receive-token"
            document, status, origin_requests = self.run_server_case(location)
        finally:
            destination.shutdown()
            thread.join()
            destination.server_close()
        self.assertEqual(status, 1)
        self.assertEqual(len(origin_requests), 1)
        self.assertEqual(destination_requests, [])
        self.assertEqual(document["results"][0]["reason"], "http-302")

    def test_stalled_complete_response_is_bounded_one_request_transport_failure(self):
        requests = 0

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802
                nonlocal requests
                requests += 1
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", "200")
                self.end_headers()
                self.wfile.write(b"{")
                self.wfile.flush()
                time.sleep(0.6)

            def log_message(self, _format, *_args):
                return

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def factory(_host: str, timeout: float) -> http.client.HTTPConnection:
            return http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=timeout)

        value = projection(
            repositories={PRIVATE_NAME: repository(PRIVATE_NAME, visibility="private", policy=None)}
        )
        stdout = io.StringIO()
        stderr = io.StringIO()
        started = time.monotonic()
        try:
            client = gaps.GitHubClient(TOKEN, timeout=0.2, connection_factory=factory)
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                document, status = gaps.verify_projection(value, token=TOKEN, client=client)
            elapsed = time.monotonic() - started
        finally:
            server.shutdown()
            thread.join()
            server.server_close()
        self.assertEqual(requests, 1)
        self.assertLess(elapsed, 2.0)
        self.assertEqual(status, 1)
        self.assertEqual(document["results"][0]["classification"], "INDETERMINATE")
        self.assertEqual(document["results"][0]["reason"], "transport-failure")
        diagnostic_surfaces = stdout.getvalue() + stderr.getvalue()
        self.assertNotIn(TOKEN, diagnostic_surfaces)
        self.assertNotIn(PRIVATE_NAME, diagnostic_surfaces)

    def test_trickled_headers_and_body_share_one_wall_clock_deadline(self):
        valid_body = json.dumps({"approval_policy": POLICY}).encode()
        headers = (
            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
            + f"Content-Length: {len(valid_body)}\r\nConnection: close\r\n\r\n".encode()
        )
        cases = {
            "headers": [bytes((byte,)) for byte in headers + valid_body],
            "body": [headers] + [bytes((byte,)) for byte in valid_body],
        }
        original_handler = signal.getsignal(signal.SIGALRM)

        def prior_handler(_signum, _frame):
            raise AssertionError("restored deadline fired unexpectedly")

        signal.signal(signal.SIGALRM, prior_handler)
        try:
            for label, chunks in cases.items():
                with self.subTest(case=label):
                    document, status, requests, elapsed = run_raw_http_response(
                        chunks,
                        timeout=0.5,
                        delay=0.05,
                    )
                    self.assertEqual(requests, 1)
                    self.assertLess(elapsed, 1.0)
                    self.assertEqual(status, 1)
                    self.assertEqual(
                        document["results"],
                        [
                            exact_row(
                                classification="INDETERMINATE",
                                reason="transport-failure",
                            )
                        ],
                    )
                    self.assertIs(signal.getsignal(signal.SIGALRM), prior_handler)
                    self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0.0)
            signal.signal(signal.SIGALRM, original_handler)

    def test_raw_out_of_range_statuses_are_transport_failures(self):
        for status_code in (600, 999):
            with self.subTest(status=status_code):
                document, status, requests, _ = run_raw_http_response(
                    [
                        (
                            f"HTTP/1.1 {status_code} Synthetic\r\n"
                            "Content-Length: 0\r\nConnection: close\r\n\r\n"
                        ).encode()
                    ],
                    timeout=0.5,
                    delay=0.0,
                )
                self.assertEqual(requests, 1)
                self.assertEqual(status, 1)
                self.assertEqual(
                    document["results"],
                    [
                        exact_row(
                            classification="INDETERMINATE",
                            reason="transport-failure",
                        )
                    ],
                )


class ResultContractTests(unittest.TestCase):
    def test_closed_result_rejects_extra_missing_bool_counts_and_inconsistent_rows(self):
        valid, _ = gaps.verify_projection(
            projection(),
            token=TOKEN,
            client=FakeClient([response(200, {"approval_policy": POLICY})]),
        )
        cases = {}
        extra = json.loads(json.dumps(valid))
        extra["extra"] = 1
        cases["extra-top"] = extra
        missing = json.loads(json.dumps(valid))
        del missing["results"][0]["field"]
        cases["missing-row-member"] = missing
        boolean_schema = json.loads(json.dumps(valid))
        boolean_schema["schema_version"] = True
        cases["boolean-schema"] = boolean_schema
        boolean_count = json.loads(json.dumps(valid))
        boolean_count["counts"]["MATCH"] = True
        cases["boolean-count"] = boolean_count
        inconsistent = json.loads(json.dumps(valid))
        inconsistent["counts"]["MATCH"] = 0
        cases["inconsistent-count"] = inconsistent
        bad_reason = json.loads(json.dumps(valid))
        bad_reason["results"][0]["reason"] = "policy-mismatch"
        cases["bad-combination"] = bad_reason
        leaked_unknown = json.loads(json.dumps(valid))
        leaked_unknown["results"][0]["classification"] = "INDETERMINATE"
        leaked_unknown["results"][0]["reason"] = "live-policy-unknown"
        leaked_unknown["results"][0]["live_policy"] = "future-policy"
        leaked_unknown["counts"]["MATCH"] = 0
        leaked_unknown["counts"]["INDETERMINATE"] = 1
        cases["unknown-live-leak"] = leaked_unknown
        unsupported = json.loads(json.dumps(valid))
        unsupported["results"][0]["classification"] = "SKIPPED"
        cases["unsupported-class"] = unsupported
        for label, value in cases.items():
            with self.subTest(case=label):
                with self.assertRaises(gaps.ContractError):
                    gaps.validate_results(value, projection())

    def test_cli_writes_closed_result_and_only_value_free_status(self):
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            desired = tmp / "desired.json"
            results = tmp / "results.json"
            desired.write_text(json.dumps(projection()), encoding="utf-8")
            env = os.environ.copy()
            env.pop("TF_VAR_github_token", None)
            proc = subprocess.run(
                [
                    os.fspath(Path(gaps.__file__)),
                    "verify",
                    "--desired-state",
                    os.fspath(desired),
                    "--results",
                    os.fspath(results),
                ],
                env=env,
                capture_output=True,
                text=True,
            )
            self.assertEqual(proc.returncode, 1)
            self.assertEqual(proc.stdout, "provider-gap verification completed with status 1\n")
            self.assertEqual(proc.stderr, "")
            document = json.loads(results.read_text(encoding="utf-8"))
            gaps.validate_results(document, projection())
            self.assertNotIn(TOKEN, results.read_text(encoding="utf-8"))


class DeclarationOnlyIntegrationTests(unittest.TestCase):
    def test_no_terraform_resource_consumes_provider_gap_declarations(self):
        root = Path(gaps.__file__).resolve().parents[1]
        resources = (root / "terraform" / "resources.tf").read_text(encoding="utf-8")
        outputs = (root / "terraform" / "outputs.tf").read_text(encoding="utf-8")
        self.assertNotIn("provider_gap", resources)
        self.assertIn('output "provider_gap_desired_state"', outputs)

    def test_legal_wrong_policy_drift_fails_shipped_final_gate(self):
        document, status = gaps.verify_projection(
            projection(
                repositories={"fixture": repository("fixture", policy=OTHER_POLICY)}
            ),
            token=TOKEN,
            client=FakeClient([response(200, {"approval_policy": POLICY})]),
        )
        self.assertEqual(document["results"][0]["classification"], "DRIFT")
        self.assertEqual(document["results"][0]["reason"], "policy-mismatch")
        self.assertEqual(status, 1)

        workflow = (
            Path(gaps.__file__).resolve().parents[1]
            / ".github"
            / "workflows"
            / "reusable-terraform-deploy.yaml"
        ).read_text(encoding="utf-8")
        block = re.search(
            r"(?ms)^      - name: Enforce provider-gap verification result\n"
            r".*?(?=^      - name: |\Z)",
            workflow,
        )
        self.assertIsNotNone(block)
        marker = "        run: |\n"
        raw = block.group(0).split(marker, 1)[1]
        script = "\n".join(
            line[10:] for line in raw.splitlines() if not line or line.startswith("          ")
        )
        env = os.environ.copy()
        env["VERIFIER_EXIT_CODE"] = str(status)
        gate = subprocess.run(
            ["bash", "-c", script], env=env, capture_output=True, text=True
        )
        self.assertNotEqual(gate.returncode, 0)


class ReporterProjectionTests(unittest.TestCase):
    def metadata_files(self, directory: Path, public: int, private: int) -> tuple[Path, Path]:
        status = directory / "metadata.status"
        metadata = directory / "metadata.json"
        status.write_text("ok\n", encoding="utf-8")
        metadata.write_text(
            json.dumps({"public_repos": public, "total_private_repos": private}),
            encoding="utf-8",
        )
        return status, metadata

    def test_shipped_reporter_projection_handles_gap_drift_and_redacts_private_target(self):
        value = projection(
            repositories={
                "public": repository("public", policy=OTHER_POLICY),
                "private": repository("private", visibility="private", policy=None),
            }
        )
        results, status = gaps.verify_projection(
            value,
            token=TOKEN,
            client=FakeClient(
                [
                    response(403, {}),
                    response(200, {"approval_policy": POLICY}),
                ]
            ),
        )
        self.assertEqual(status, 1)
        plan = plan_document()
        report = gaps.render_report(
            plan,
            value,
            results,
            is_organization=False,
            owner=OWNER,
        )
        self.assertIn("DRIFT", report)
        self.assertIn("INDETERMINATE", report)
        self.assertIn(gaps.PRIVATE_REPOSITORY_REDACTED, report)
        self.assertNotIn(f"{OWNER}/private", report)
        self.assertNotIn(POLICY, report)
        self.assertNotIn(OTHER_POLICY, report)

    def test_private_state_only_addresses_are_redacted_in_detector_and_non_detector_modes(self):
        private = "state-only-private-canary"
        dependent_address = f'github_repository_file.codeowners["{private}"]'
        repository_address = f'github_repository.repo["{private}"]'
        prior = [managed_repository_row(private, "private", address=repository_address)]
        delete = change(dependent_address, ["delete"], before={}, after=None)
        repository_delete = change(
            repository_address,
            ["delete"],
            resource_type="github_repository",
            index=private,
            before={"name": private, "visibility": "private"},
            after=None,
        )
        plan = plan_document(changes=[delete, repository_delete], prior_resources=prior)
        value = projection(repositories={})
        results, status = gaps.verify_projection(value, token=TOKEN, client=FakeClient([]))
        self.assertEqual(status, 0)
        for detector in (False, True):
            with self.subTest(detector=detector):
                rendered = gaps.render_summary(
                    plan,
                    value,
                    results if detector else None,
                    detector=detector,
                    is_organization=False,
                    owner=OWNER,
                )
                self.assertIn(gaps.PRIVATE_RESOURCE_REDACTED, rendered)
                self.assertNotIn(private, rendered)
                self.assertNotIn(repository_address, rendered)
                self.assertNotIn(dependent_address, rendered)

    def test_distinct_private_instance_key_is_redacted_from_every_rendered_surface(self):
        private_name = "synthetic-private-name-a1"
        instance_key = "synthetic-private-key-b2"
        repository_address = f'github_repository.repo["{instance_key}"]'
        dependent_address = f'github_repository_file.codeowners["{instance_key}"]'
        value = projection(repositories={})
        results = gaps.result_document([])

        def state_row(visibility: str) -> dict:
            return managed_repository_row(
                private_name,
                visibility,
                address=repository_address,
                index=instance_key,
            )

        def repository_change(before_visibility: str, after_visibility: str) -> dict:
            return change(
                repository_address,
                ["update"],
                resource_type="github_repository",
                index=instance_key,
                before={"name": private_name, "visibility": before_visibility},
                after={"name": private_name, "visibility": after_visibility},
            )

        cases = {
            "prior_state": (
                [state_row("private")],
                [state_row("public")],
                repository_change("public", "public"),
            ),
            "planned_values": (
                [state_row("public")],
                [state_row("private")],
                repository_change("public", "public"),
            ),
            "change_before": (
                [state_row("public")],
                [state_row("public")],
                repository_change("private", "public"),
            ),
            "change_after": (
                [state_row("public")],
                [state_row("public")],
                repository_change("public", "private"),
            ),
        }
        dependent_change = change(
            dependent_address,
            ["update"],
            resource_type="github_repository_file",
            index=instance_key,
            before={},
            after={},
        )

        for source, (prior, planned, repository_change_row) in cases.items():
            with self.subTest(source=source):
                plan = plan_document(
                    changes=[repository_change_row, dependent_change],
                    prior_resources=prior,
                    planned_resources=planned,
                )
                self.assertEqual(
                    gaps.private_redaction_set(plan, value),
                    {private_name, instance_key},
                )
                stdout = io.StringIO()
                stderr = io.StringIO()
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                    non_detector_summary = gaps.render_summary(
                        plan,
                        value,
                        None,
                        detector=False,
                        is_organization=False,
                        owner=OWNER,
                    )
                    detector_summary = gaps.render_summary(
                        plan,
                        value,
                        results,
                        detector=True,
                        is_organization=False,
                        owner=OWNER,
                    )
                    report = gaps.render_report(
                        plan,
                        value,
                        results,
                        is_organization=False,
                        owner=OWNER,
                    )
                surfaces = "\n".join(
                    (
                        stdout.getvalue(),
                        stderr.getvalue(),
                        non_detector_summary,
                        detector_summary,
                        report,
                        "",  # No annotation is produced by either renderer.
                    )
                )
                for secret in (
                    private_name,
                    instance_key,
                    repository_address,
                    dependent_address,
                ):
                    self.assertNotIn(secret, surfaces)
                self.assertEqual(
                    non_detector_summary.count("<private-resource-redacted>"), 2
                )
                self.assertEqual(
                    detector_summary.count("<private-resource-redacted>"), 2
                )
                self.assertEqual(report.count("<private-resource-redacted>"), 2)

    def test_three_plane_all_clear_requires_every_plane_empty(self):
        value = projection(
            organization=True,
            organization_policy=POLICY,
            repositories={},
        )
        results, status = gaps.verify_projection(
            value,
            token=TOKEN,
            client=FakeClient([response(200, {"approval_policy": POLICY})]),
        )
        self.assertEqual(status, 0)
        with tempfile.TemporaryDirectory() as raw_tmp:
            tmp = Path(raw_tmp)
            metadata_status, metadata = self.metadata_files(tmp, 0, 0)
            plan = plan_document(
                prior_resources=[inventory_data("owner", []), inventory_data("public", [])]
            )
            summary = gaps.render_summary(
                plan,
                value,
                results,
                detector=True,
                is_organization=True,
                owner=OWNER,
                metadata_status_path=metadata_status,
                metadata_path=metadata,
            )
        self.assertIn("No actionable Terraform resource changes", summary)
        self.assertIn("No actionable inventory findings", summary)
        self.assertIn("No actionable provider-gap findings", summary)
        self.assertIn("Infrastructure matches", summary)


@unittest.skipUnless(
    os.environ.get("PROVIDER_GAP_LIVE_PRIVATE") == "1",
    "set PROVIDER_GAP_LIVE_PRIVATE=1 for the sanitized live private-422 proof",
)
class LivePrivateContractTests(unittest.TestCase):
    def test_session_credential_real_private_422_through_shipped_client(self):
        token_proc = subprocess.run(
            ["gh", "auth", "token"], capture_output=True, text=True
        )
        repos_proc = subprocess.run(
            [
                "gh",
                "api",
                "--method",
                "GET",
                "--paginate",
                "--slurp",
                "/user/repos?affiliation=owner&visibility=private&per_page=100",
            ],
            capture_output=True,
            text=True,
        )
        if token_proc.returncode != 0 or repos_proc.returncode != 0:
            self.fail("session credential live GET setup failed")
        try:
            pages = json.loads(repos_proc.stdout)
            owned_private = [
                item
                for page in pages
                for item in page
                if item.get("private") is True and item.get("owner", {}).get("login")
            ]
            selected = owned_private[0]
            owner = selected["owner"]["login"]
            name = selected["name"]
        except (IndexError, KeyError, TypeError, json.JSONDecodeError):
            self.fail("session credential did not expose a usable private repository")
        value = projection(
            repositories={name: repository(name, visibility="private", policy=None)}
        )
        value["github_owner"] = owner
        document, status = gaps.verify_projection(value, token=token_proc.stdout.strip())
        if status != 0:
            row = document["results"][0]
            self.fail(
                "real private endpoint did not produce a non-actionable result: "
                f"{row['classification']} / {row['reason']}"
            )
        row = document["results"][0]
        if row["classification"] != "NOT-APPLICABLE" or row["reason"] != "private-repository":
            self.fail("real private endpoint did not satisfy the exact 422 contract")


if __name__ == "__main__":
    unittest.main(verbosity=2)
