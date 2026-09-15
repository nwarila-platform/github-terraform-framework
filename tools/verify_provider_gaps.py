#!/usr/bin/env python3
"""Verify declaration-only GitHub provider gaps and render sanitized reports.

The verifier intentionally has no mutation path: it constructs only the two
documented fork-PR contributor-approval GET endpoints, sends one request per
requestable target, and never follows redirects.  The rendering helpers are
also used by the reusable workflow so its two public projections share the
same closed-contract validation and private-repository redaction boundary.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import sys
import time
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable
from urllib.parse import quote


API_HOST = "api.github.com"
API_ORIGIN = f"https://{API_HOST}"
API_VERSION = "2026-03-10"
REQUEST_TIMEOUT_SECONDS = 30.0
MAX_RESPONSE_BYTES = 1024 * 1024

POLICIES = frozenset(
    {
        "first_time_contributors_new_to_github",
        "first_time_contributors",
        "all_external_contributors",
    }
)
CLASSIFICATIONS = (
    "MATCH",
    "DRIFT",
    "NOT-APPLICABLE",
    "INDETERMINATE",
    "DECLARATION-ERROR",
)
ACTIONABLE_GAP_CLASSES = frozenset(
    {"DRIFT", "INDETERMINATE", "DECLARATION-ERROR"}
)
RESULT_KEYS = frozenset(
    {
        "target_kind",
        "target",
        "field",
        "classification",
        "declared_policy",
        "live_policy",
        "reason",
    }
)
TOP_LEVEL_KEYS = frozenset(
    {
        "schema_version",
        "github_owner",
        "github_is_organization",
        "organization_provider_gaps",
        "repositories",
    }
)
ORGANIZATION_GAP_KEYS = frozenset(
    {"fork_pr_contributor_approval", "code_security_configuration"}
)
CODE_SECURITY_KEYS = frozenset({"id", "enforcement", "defaults", "status"})
REPOSITORY_KEYS = frozenset({"name", "visibility", "archived", "provider_gaps"})
REPOSITORY_GAP_KEYS = frozenset({"fork_pr_contributor_approval"})
OWNER_RE = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$")
REPOSITORY_RE = re.compile(r"^[A-Za-z0-9._-]+$")
HTTP_REASON_RE = re.compile(r"^http-([0-9]{3})$")
PRIVATE_422_ERROR = "Fork PR approval is not allowed for private repositories."

INVENTORY_ADDRESS = "check.inventory_complete"
INVENTORY_UNVERIFIED = (
    "Repository enumeration could not be verified against organization metadata."
)
PRIVATE_REPOSITORY_REDACTED = "<private-repository-redacted>"
PRIVATE_RESOURCE_REDACTED = "<private-resource-redacted>"


class ContractError(ValueError):
    """An input does not satisfy a closed JSON or plan projection contract."""


class TransportFailure(Exception):
    """A request did not yield one complete HTTP response before its deadline."""


def _is_json_number(value: Any) -> bool:
    return (type(value) is int or type(value) is float) and not isinstance(value, bool)


def _require_exact_keys(value: Any, expected: frozenset[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise ContractError(f"invalid {label}")
    return value


def _reject_duplicate_members(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ContractError("duplicate JSON member")
        result[key] = value
    return result


def _reject_nonstandard_number(_value: str) -> Any:
    raise ContractError("non-standard JSON number")


def loads_strict(text: str) -> Any:
    """Decode JSON while rejecting duplicate members at every object level."""
    try:
        return json.loads(
            text,
            object_pairs_hook=_reject_duplicate_members,
            parse_constant=_reject_nonstandard_number,
        )
    except ContractError:
        raise
    except (json.JSONDecodeError, UnicodeError, RecursionError) as exc:
        raise ContractError("invalid JSON") from exc


def load_json_strict(path: str | Path) -> Any:
    try:
        text = Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        raise ContractError("unreadable JSON input") from exc
    return loads_strict(text)


def validate_desired_state(value: Any) -> dict[str, Any]:
    """Validate and return the exact planned provider-gap output value."""
    projection = _require_exact_keys(value, TOP_LEVEL_KEYS, "desired-state projection")
    if not _is_json_number(projection["schema_version"]) or projection["schema_version"] != 1:
        raise ContractError("invalid schema version")

    owner = projection["github_owner"]
    if not isinstance(owner, str) or not owner or OWNER_RE.fullmatch(owner) is None:
        raise ContractError("invalid owner")
    if type(projection["github_is_organization"]) is not bool:
        raise ContractError("invalid owner kind")

    organization_gaps = projection["organization_provider_gaps"]
    if organization_gaps is not None:
        organization_gaps = _require_exact_keys(
            organization_gaps, ORGANIZATION_GAP_KEYS, "organization provider gaps"
        )
        policy = organization_gaps["fork_pr_contributor_approval"]
        if policy is not None and (not isinstance(policy, str) or policy not in POLICIES):
            raise ContractError("invalid organization policy")
        security = organization_gaps["code_security_configuration"]
        if security is not None:
            security = _require_exact_keys(
                security, CODE_SECURITY_KEYS, "code security configuration"
            )
            if not _is_json_number(security["id"]):
                raise ContractError("invalid code security id")
            if not isinstance(security["enforcement"], str):
                raise ContractError("invalid code security enforcement")
            if not isinstance(security["status"], str):
                raise ContractError("invalid code security status")
            defaults = security["defaults"]
            if not isinstance(defaults, list) or not all(
                isinstance(item, str) for item in defaults
            ):
                raise ContractError("invalid code security defaults")

    if (
        not projection["github_is_organization"]
        and organization_gaps is not None
        and organization_gaps["fork_pr_contributor_approval"] is not None
    ):
        raise ContractError("personal owner has organization fork policy")

    repositories = projection["repositories"]
    if not isinstance(repositories, dict):
        raise ContractError("invalid repository collection")
    canonical_names: set[str] = set()
    for key, raw_repository in repositories.items():
        if not isinstance(key, str):
            raise ContractError("invalid repository key")
        repository = _require_exact_keys(raw_repository, REPOSITORY_KEYS, "repository")
        name = repository["name"]
        if (
            not isinstance(name, str)
            or not name
            or key != name
            or len(name) > 100
            or name in (".", "..")
            or REPOSITORY_RE.fullmatch(name) is None
        ):
            raise ContractError("invalid repository name")
        canonical = name.lower()
        if canonical in canonical_names:
            raise ContractError("duplicate canonical repository target")
        canonical_names.add(canonical)
        if repository["visibility"] not in ("public", "private", "internal"):
            raise ContractError("invalid repository visibility")
        if type(repository["archived"]) is not bool:
            raise ContractError("invalid repository archived value")
        gaps = repository["provider_gaps"]
        if gaps is not None:
            gaps = _require_exact_keys(gaps, REPOSITORY_GAP_KEYS, "repository provider gaps")
            policy = gaps["fork_pr_contributor_approval"]
            if not isinstance(policy, str) or policy not in POLICIES:
                raise ContractError("invalid repository policy")
    return projection


def _repository_policy(repository: dict[str, Any]) -> str | None:
    gaps = repository["provider_gaps"]
    return None if gaps is None else gaps["fork_pr_contributor_approval"]


def desired_targets(projection: dict[str, Any]) -> list[dict[str, Any]]:
    """Return the exact ordered target set and its effective declaration."""
    projection = validate_desired_state(projection)
    owner = projection["github_owner"]
    organization_gaps = projection["organization_provider_gaps"]
    organization_policy = (
        None
        if organization_gaps is None
        else organization_gaps["fork_pr_contributor_approval"]
    )
    targets: list[dict[str, Any]] = []
    if projection["github_is_organization"]:
        targets.append(
            {
                "target_kind": "organization",
                "target": owner,
                "name": owner,
                "visibility": None,
                "archived": False,
                "declared_policy": organization_policy,
            }
        )
    for name in sorted(projection["repositories"]):
        repository = projection["repositories"][name]
        explicit = _repository_policy(repository)
        if repository["visibility"] == "private":
            effective = explicit
        elif projection["github_is_organization"]:
            effective = explicit if explicit is not None else organization_policy
        else:
            effective = explicit
        targets.append(
            {
                "target_kind": "repository",
                "target": f"{owner}/{name}",
                "name": name,
                "visibility": repository["visibility"],
                "archived": repository["archived"],
                "declared_policy": effective,
            }
        )
    return targets


def _row(
    target: dict[str, Any],
    classification: str,
    reason: str,
    *,
    live_policy: str | None = None,
) -> dict[str, Any]:
    return {
        "target_kind": target["target_kind"],
        "target": target["target"],
        "field": "fork_pr_contributor_approval",
        "classification": classification,
        "declared_policy": target["declared_policy"],
        "live_policy": live_policy,
        "reason": reason,
    }


def invalid_projection_result() -> dict[str, Any]:
    return {
        "target_kind": "projection",
        "target": "provider_gap_desired_state",
        "field": "provider_gap_desired_state",
        "classification": "DECLARATION-ERROR",
        "declared_policy": None,
        "live_policy": None,
        "reason": "invalid-desired-state-projection",
    }


def result_document(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    materialized = list(rows)
    counts = {classification: 0 for classification in CLASSIFICATIONS}
    for row in materialized:
        counts[row["classification"]] += 1
    return {"schema_version": 1, "counts": counts, "results": materialized}


@dataclass(frozen=True)
class HttpResponse:
    status: int
    body: bytes


ConnectionFactory = Callable[[str, float], http.client.HTTPConnection]


class GitHubClient:
    """Minimal deadline-bound, no-redirect GitHub GET client."""

    def __init__(
        self,
        token: str,
        *,
        timeout: float = REQUEST_TIMEOUT_SECONDS,
        connection_factory: ConnectionFactory | None = None,
    ) -> None:
        self._token = token
        self._timeout = timeout
        self._connection_factory = connection_factory or self._https_connection

    @staticmethod
    def _https_connection(host: str, timeout: float) -> http.client.HTTPConnection:
        return http.client.HTTPSConnection(host, port=443, timeout=timeout)

    @staticmethod
    def _set_socket_timeout(connection: http.client.HTTPConnection, remaining: float) -> None:
        sock = getattr(connection, "sock", None)
        if sock is not None:
            sock.settimeout(remaining)

    def get(self, path: str) -> HttpResponse:
        if not path.startswith("/") or "?" in path or "#" in path:
            raise TransportFailure
        deadline = time.monotonic() + self._timeout
        connection: http.client.HTTPConnection | None = None

        def remaining() -> float:
            value = deadline - time.monotonic()
            if value <= 0:
                raise TimeoutError
            return value

        try:
            connection = self._connection_factory(API_HOST, self._timeout)
            connection.connect()
            self._set_socket_timeout(connection, remaining())
            connection.request(
                "GET",
                path,
                headers={
                    "Accept": "application/vnd.github+json",
                    "Authorization": f"Bearer {self._token}",
                    "User-Agent": "github-terraform-framework-provider-gap-verifier/1",
                    "X-GitHub-Api-Version": API_VERSION,
                },
            )
            self._set_socket_timeout(connection, remaining())
            response = connection.getresponse()
            if type(response.status) is not int:
                raise TransportFailure
            body = bytearray()
            while True:
                self._set_socket_timeout(connection, remaining())
                chunk = response.read(65536)
                if not chunk:
                    break
                body.extend(chunk)
                if len(body) > MAX_RESPONSE_BYTES:
                    raise TransportFailure
            return HttpResponse(response.status, bytes(body))
        except Exception as exc:
            raise TransportFailure from exc
        finally:
            if connection is not None:
                try:
                    connection.close()
                except Exception:
                    pass


def target_path(target: dict[str, Any], owner: str) -> str:
    encoded_owner = quote(owner, safe="")
    if target["target_kind"] == "organization":
        return f"/orgs/{encoded_owner}/actions/permissions/fork-pr-contributor-approval"
    encoded_repository = quote(target["name"], safe="")
    return (
        f"/repos/{encoded_owner}/{encoded_repository}/actions/permissions/"
        "fork-pr-contributor-approval"
    )


def _decode_response_object(body: bytes) -> Any:
    try:
        return json.loads(body.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ContractError("malformed response JSON") from exc


def classify_response(target: dict[str, Any], response: HttpResponse) -> dict[str, Any]:
    """Apply the ordered response classifier after declaration/credential checks."""
    if target["visibility"] == "private":
        if response.status != 422:
            return _row(target, "INDETERMINATE", f"http-{response.status}")
        try:
            body = _decode_response_object(response.body)
        except ContractError:
            body = None
        if isinstance(body, dict) and body.get("errors") == PRIVATE_422_ERROR and isinstance(
            body.get("errors"), str
        ):
            return _row(target, "NOT-APPLICABLE", "private-repository")
        return _row(target, "INDETERMINATE", "private-422-contract-mismatch")

    if response.status != 200:
        return _row(target, "INDETERMINATE", f"http-{response.status}")
    try:
        body = _decode_response_object(response.body)
    except ContractError:
        return _row(target, "INDETERMINATE", "malformed-json")
    if not isinstance(body, dict):
        return _row(target, "INDETERMINATE", "response-not-object")
    if "approval_policy" not in body:
        return _row(target, "INDETERMINATE", "approval-policy-missing")
    live_policy = body["approval_policy"]
    if not isinstance(live_policy, str):
        return _row(target, "INDETERMINATE", "approval-policy-not-string")
    if live_policy not in POLICIES:
        return _row(target, "INDETERMINATE", "live-policy-unknown")
    if live_policy == target["declared_policy"]:
        return _row(target, "MATCH", "policy-match", live_policy=live_policy)
    return _row(target, "DRIFT", "policy-mismatch", live_policy=live_policy)


def verify_projection(
    value: Any,
    *,
    token: str | None,
    client: GitHubClient | None = None,
) -> tuple[dict[str, Any], int]:
    """Validate and verify a projection, returning its closed result and exit code."""
    try:
        projection = validate_desired_state(value)
        targets = desired_targets(projection)
    except ContractError:
        document = result_document([invalid_projection_result()])
        validate_results(document)
        return document, 1

    rows: list[dict[str, Any]] = []
    requestable: list[dict[str, Any]] = []
    for target in targets:
        declared = target["declared_policy"]
        if target["visibility"] == "private" and declared is not None:
            rows.append(_row(target, "DECLARATION-ERROR", "private-declaration-forbidden"))
        elif target["visibility"] != "private" and declared is None:
            rows.append(_row(target, "DECLARATION-ERROR", "declaration-missing"))
        else:
            requestable.append(target)

    if token is None or token == "":
        rows.extend(_row(target, "INDETERMINATE", "credential-missing") for target in requestable)
    else:
        http_client = client or GitHubClient(token)
        owner = projection["github_owner"]
        for target in requestable:
            try:
                response = http_client.get(target_path(target, owner))
            except TransportFailure:
                rows.append(_row(target, "INDETERMINATE", "transport-failure"))
            else:
                rows.append(classify_response(target, response))

    order = {(target["target_kind"], target["target"]): index for index, target in enumerate(targets)}
    rows.sort(key=lambda row: order[(row["target_kind"], row["target"])])
    document = result_document(rows)
    validate_results(document, projection)
    exit_code = int(any(row["classification"] in ACTIONABLE_GAP_CLASSES for row in rows))
    return document, exit_code


def verify_text(
    text: str,
    *,
    token: str | None,
    client: GitHubClient | None = None,
) -> tuple[dict[str, Any], int]:
    try:
        value = loads_strict(text)
    except ContractError:
        document = result_document([invalid_projection_result()])
        validate_results(document)
        return document, 1
    return verify_projection(value, token=token, client=client)


def _write_json(path: str | Path, value: Any) -> None:
    destination = Path(path)
    temporary = destination.with_name(destination.name + ".tmp")
    try:
        temporary.write_text(
            json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
        temporary.replace(destination)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def run_verifier(
    desired_state_path: str | Path,
    results_path: str | Path,
    *,
    environ: dict[str, str] | os._Environ[str] | None = None,
    client: GitHubClient | None = None,
) -> int:
    environment = os.environ if environ is None else environ
    try:
        text = Path(desired_state_path).read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        text = ""
    document, exit_code = verify_text(
        text,
        token=environment.get("TF_VAR_github_token"),
        client=client,
    )
    _write_json(results_path, document)
    return exit_code


def _validate_projection_error_row(row: dict[str, Any]) -> None:
    expected = invalid_projection_result()
    if row != expected:
        raise ContractError("invalid projection-error result")


def _validate_target_row(row: dict[str, Any], target: dict[str, Any]) -> None:
    if set(row) != RESULT_KEYS:
        raise ContractError("invalid result row members")
    if row["target_kind"] != target["target_kind"] or row["target"] != target["target"]:
        raise ContractError("invalid result target")
    if row["field"] != "fork_pr_contributor_approval":
        raise ContractError("invalid result field")
    classification = row["classification"]
    if classification not in CLASSIFICATIONS:
        raise ContractError("invalid result classification")
    declared = row["declared_policy"]
    live = row["live_policy"]
    if declared != target["declared_policy"]:
        raise ContractError("inconsistent declared policy")
    if live is not None and (not isinstance(live, str) or live not in POLICIES):
        raise ContractError("invalid live policy")
    if not isinstance(row["reason"], str):
        raise ContractError("invalid result reason")
    reason = row["reason"]
    private = target["visibility"] == "private"

    if private and declared is not None:
        valid = (
            classification == "DECLARATION-ERROR"
            and reason == "private-declaration-forbidden"
            and live is None
        )
    elif not private and declared is None:
        valid = (
            classification == "DECLARATION-ERROR"
            and reason == "declaration-missing"
            and live is None
        )
    elif classification == "MATCH":
        valid = reason == "policy-match" and declared is not None and live == declared
    elif classification == "DRIFT":
        valid = (
            reason == "policy-mismatch"
            and declared is not None
            and live is not None
            and live != declared
        )
    elif classification == "NOT-APPLICABLE":
        valid = private and declared is None and reason == "private-repository" and live is None
    elif classification == "INDETERMINATE":
        general = {
            "credential-missing",
            "transport-failure",
        }
        response_reasons = {
            "malformed-json",
            "response-not-object",
            "approval-policy-missing",
            "approval-policy-not-string",
            "live-policy-unknown",
        }
        valid = live is None and (
            reason in general
            or HTTP_REASON_RE.fullmatch(reason) is not None
            or (private and reason == "private-422-contract-mismatch")
            or (not private and reason in response_reasons)
        )
    else:
        valid = False
    if not valid:
        raise ContractError("invalid class/reason/policy combination")


def validate_results(
    value: Any,
    projection: dict[str, Any] | None = None,
) -> dict[str, Any]:
    document = _require_exact_keys(
        value, frozenset({"schema_version", "counts", "results"}), "result document"
    )
    if not _is_json_number(document["schema_version"]) or document["schema_version"] != 1:
        raise ContractError("invalid result schema version")
    counts = _require_exact_keys(document["counts"], frozenset(CLASSIFICATIONS), "counts")
    if any(type(counts[key]) is not int or counts[key] < 0 for key in CLASSIFICATIONS):
        raise ContractError("invalid result counts")
    rows = document["results"]
    if not isinstance(rows, list) or sum(counts.values()) != len(rows):
        raise ContractError("inconsistent result counts")
    actual_counts = Counter()
    for row in rows:
        if not isinstance(row, dict) or row.get("classification") not in CLASSIFICATIONS:
            raise ContractError("invalid result row")
        actual_counts[row["classification"]] += 1
    if any(actual_counts[key] != counts[key] for key in CLASSIFICATIONS):
        raise ContractError("incorrect result counts")

    if projection is None:
        if len(rows) != 1:
            raise ContractError("result targets require desired-state projection")
        _validate_projection_error_row(rows[0])
        return document

    targets = desired_targets(validate_desired_state(projection))
    if len(rows) != len(targets):
        raise ContractError("incorrect result target count")
    for row, target in zip(rows, targets):
        _validate_target_row(row, target)
    return document


def load_results(path: str | Path, projection: dict[str, Any]) -> dict[str, Any]:
    return validate_results(load_json_strict(path), projection)


def load_plan(path: str | Path) -> dict[str, Any]:
    plan = load_json_strict(path)
    if not isinstance(plan, dict):
        raise ContractError("invalid plan")
    for member in ("prior_state", "planned_values", "resource_changes"):
        if member not in plan:
            raise ContractError("missing required plan member")
    if not isinstance(plan["resource_changes"], list):
        raise ContractError("invalid resource changes")
    return plan


def _module_resources(root: Any) -> Iterable[dict[str, Any]]:
    if not isinstance(root, dict):
        raise ContractError("invalid root module")
    resources = root.get("resources", [])
    children = root.get("child_modules", [])
    if not isinstance(resources, list) or not isinstance(children, list):
        raise ContractError("invalid module resources")
    for resource in resources:
        if not isinstance(resource, dict):
            raise ContractError("invalid resource instance")
        yield resource
    for child in children:
        yield from _module_resources(child)


def _state_root(plan: dict[str, Any], state_member: str) -> dict[str, Any]:
    state = plan[state_member]
    if not isinstance(state, dict):
        raise ContractError("invalid state projection")
    if state_member == "prior_state":
        values = state.get("values")
        if not isinstance(values, dict):
            raise ContractError("invalid prior state values")
    else:
        values = state
    root = values.get("root_module")
    if not isinstance(root, dict):
        raise ContractError("missing root module")
    return root


def _validate_repository_instance(resource: dict[str, Any], values: Any) -> tuple[str, str, str]:
    if resource.get("mode") != "managed" or resource.get("type") != "github_repository":
        raise ContractError("invalid repository instance")
    address = resource.get("address")
    index = resource.get("index")
    if not isinstance(address, str) or not address or not isinstance(index, str) or not index:
        raise ContractError("invalid repository address or key")
    if not isinstance(values, dict):
        raise ContractError("invalid repository values")
    name = values.get("name")
    visibility = values.get("visibility")
    if (
        not isinstance(name, str)
        or not name
        or len(name) > 100
        or name in (".", "..")
        or REPOSITORY_RE.fullmatch(name) is None
        or visibility not in ("public", "private", "internal")
    ):
        raise ContractError("invalid repository name or visibility")
    return name, index, visibility


def private_redaction_set(plan: dict[str, Any], projection: dict[str, Any]) -> set[str]:
    """Build the fail-closed union of desired, prior, planned, before, and after names/keys."""
    validate_desired_state(projection)
    redactions = {
        name
        for name, repository in projection["repositories"].items()
        if repository["visibility"] == "private"
    }

    for state_member in ("prior_state", "planned_values"):
        for resource in _module_resources(_state_root(plan, state_member)):
            if resource.get("type") != "github_repository":
                continue
            name, index, visibility = _validate_repository_instance(
                resource, resource.get("values")
            )
            if visibility == "private":
                redactions.update((name, index))

    for resource in plan["resource_changes"]:
        if not isinstance(resource, dict):
            raise ContractError("invalid resource change")
        if resource.get("type") != "github_repository":
            continue
        change = resource.get("change")
        if not isinstance(change, dict) or "before" not in change or "after" not in change:
            raise ContractError("invalid repository change")
        saw_values = False
        for member in ("before", "after"):
            values = change[member]
            if values is None:
                continue
            saw_values = True
            name, index, visibility = _validate_repository_instance(resource, values)
            if visibility == "private":
                redactions.update((name, index))
        if not saw_values:
            raise ContractError("unclassifiable repository change")
    return redactions


def redact_address(address: str, redactions: set[str]) -> str:
    folded = address.lower()
    if any(item.lower() in folded for item in redactions):
        return PRIVATE_RESOURCE_REDACTED
    return address


def terraform_rows(plan: dict[str, Any], redactions: set[str]) -> list[tuple[str, str, list[str]]]:
    rows: list[tuple[str, str, list[str]]] = []
    for resource in plan["resource_changes"]:
        if not isinstance(resource, dict):
            raise ContractError("invalid resource change")
        address = resource.get("address")
        change = resource.get("change")
        if not isinstance(address, str) or not address or not isinstance(change, dict):
            raise ContractError("invalid resource change")
        actions = change.get("actions")
        if not isinstance(actions, list) or not actions or not all(
            isinstance(action, str) and action for action in actions
        ):
            raise ContractError("invalid resource actions")
        action = "-".join(actions)
        if action in ("no-op", "read"):
            continue
        classification = (
            "INDETERMINATE / state-binding-missing"
            if actions == ["create"]
            else "DRIFT / live-mismatch"
        )
        rows.append((redact_address(address, redactions), classification, actions))
    return rows


def inventory_check(plan: dict[str, Any]) -> tuple[str, list[str]]:
    checks = plan.get("checks")
    if not isinstance(checks, list):
        return "unverified", []
    matches = [
        entry
        for entry in checks
        if isinstance(entry, dict)
        and isinstance(entry.get("address"), dict)
        and entry["address"].get("to_display") == INVENTORY_ADDRESS
    ]
    if len(matches) != 1:
        return "unverified", []
    entry = matches[0]
    address = entry.get("address")
    status = entry.get("status")
    instances = entry.get("instances")
    if (
        address.get("kind") != "check"
        or address.get("name") != "inventory_complete"
        or status not in ("pass", "fail")
        or not isinstance(instances, list)
        or len(instances) != 1
        or not isinstance(instances[0], dict)
        or instances[0].get("status") != status
    ):
        return "unverified", []
    if status == "pass":
        if instances[0].get("problems") not in (None, []):
            return "unverified", []
        return "pass", []
    problems = instances[0].get("problems")
    if not isinstance(problems, list) or not problems:
        return "unverified", []
    messages = []
    for problem in problems:
        if not isinstance(problem, dict):
            return "unverified", []
        message = problem.get("message")
        if not isinstance(message, str) or not message.strip():
            return "unverified", []
        messages.append(message)
    return "fail", messages


def inventory_enumeration(
    plan: dict[str, Any],
    *,
    owner: str,
    metadata_status_path: str | Path,
    metadata_path: str | Path,
) -> str:
    if OWNER_RE.fullmatch(owner) is None:
        return "unverified"
    try:
        resources = list(_module_resources(_state_root(plan, "prior_state")))
    except ContractError:
        return "unverified"

    def rows(name: str) -> list[dict[str, Any]]:
        return [
            row
            for row in resources
            if row.get("mode") == "data"
            and row.get("type") == "github_repositories"
            and row.get("name") == name
            and row.get("index") == owner
        ]

    owner_rows = rows("owner")
    public_rows = rows("public")
    if len(owner_rows) != 1 or len(public_rows) != 1:
        return "unverified"
    owner_values = owner_rows[0].get("values")
    public_values = public_rows[0].get("values")
    if not isinstance(owner_values, dict) or not isinstance(public_values, dict):
        return "unverified"
    owner_names = owner_values.get("names")
    public_names = public_values.get("names")
    if (
        not isinstance(owner_names, list)
        or not isinstance(public_names, list)
        or not all(isinstance(name, str) for name in owner_names)
        or not all(isinstance(name, str) for name in public_names)
    ):
        return "unverified"
    owner_set = set(owner_names)
    public_set = set(public_names)
    if (
        len(owner_names) != len(owner_set)
        or len(public_names) != len(public_set)
        or not public_set.issubset(owner_set)
    ):
        return "unverified"
    try:
        metadata_status = Path(metadata_status_path).read_text(encoding="utf-8").strip()
        metadata = load_json_strict(metadata_path)
    except (OSError, UnicodeError, ContractError):
        return "unverified"
    if metadata_status != "ok" or not isinstance(metadata, dict):
        return "unverified"
    public_repos = metadata.get("public_repos")
    private_repos = metadata.get("total_private_repos")
    if (
        type(public_repos) is not int
        or type(private_repos) is not int
        or public_repos < 0
        or private_repos < 0
    ):
        return "unverified"
    owner_total = public_repos + private_repos
    if owner_total >= 1000:
        return "unverified"
    if len(owner_set) != owner_total or len(public_set) != public_repos:
        return "unverified"
    return "pass"


def _gap_display_rows(
    results: dict[str, Any], projection: dict[str, Any], *, actionable_only: bool
) -> list[tuple[str, str, str, str]]:
    visibilities = {
        f"{projection['github_owner']}/{name}": repository["visibility"]
        for name, repository in projection["repositories"].items()
    }
    rows = []
    for result in results["results"]:
        if actionable_only and result["classification"] not in ACTIONABLE_GAP_CLASSES:
            continue
        target = result["target"]
        if result["target_kind"] == "repository" and visibilities[target] == "private":
            target = PRIVATE_REPOSITORY_REDACTED
        rows.append(
            (target, result["field"], result["classification"], result["reason"])
        )
    return rows


def _render_terraform_section(
    lines: list[str], rows: list[tuple[str, str, list[str]]], *, detector: bool
) -> None:
    if detector:
        lines.extend(("#### Terraform resource changes", ""))
    if not rows:
        lines.append("No actionable Terraform resource changes.")
        return
    tally = Counter("-".join(actions) for _, _, actions in rows)
    lines.extend(("| count | action |", "|---|---|"))
    for action, count in sorted(tally.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {count} | `{action}` |")
    lines.extend(("", "| resource | action |", "|---|---|"))
    for address, _, actions in sorted(rows):
        lines.append(f"| `{address}` | `{'-'.join(actions)}` |")
    lines.extend(
        (
            "",
            "_Values omitted by design (public repo). Run a real-state plan out-of-band for full detail._",
        )
    )


def render_summary(
    plan: dict[str, Any],
    projection: dict[str, Any],
    results: dict[str, Any] | None,
    *,
    detector: bool,
    is_organization: bool,
    owner: str,
    metadata_status_path: str | Path = "inventory-metadata.status",
    metadata_path: str | Path = "inventory-metadata.json",
) -> str:
    projection = validate_desired_state(projection)
    if projection["github_owner"] != owner or projection["github_is_organization"] != is_organization:
        raise ContractError("workflow owner does not match projection")
    redactions = private_redaction_set(plan, projection)
    tf_rows = terraform_rows(plan, redactions)
    validated_results = None
    if detector:
        if results is None:
            raise ContractError("missing provider-gap results")
        validated_results = validate_results(results, projection)
    elif results is not None:
        raise ContractError("non-detector projection received results")

    lines = ["### Terraform plan — sanitized", ""]
    _render_terraform_section(lines, tf_rows, detector=detector)
    if not detector:
        return "\n".join(lines) + "\n"

    inventory_actionable = False
    if is_organization:
        check_status, check_messages = inventory_check(plan)
        enumeration_status = inventory_enumeration(
            plan,
            owner=owner,
            metadata_status_path=metadata_status_path,
            metadata_path=metadata_path,
        )
        if check_status == "fail":
            inventory_actionable = True
            lines.extend(("", "INVENTORY / undeclared-live:"))
            lines.extend(check_messages)
        if check_status == "unverified" or enumeration_status == "unverified":
            inventory_actionable = True
            lines.extend(("", f"INVENTORY / enumeration-unverified: {INVENTORY_UNVERIFIED}"))
        if check_status == "pass" and enumeration_status != "unverified":
            lines.extend(("", "No actionable inventory findings."))

    assert validated_results is not None
    lines.extend(("", "#### Provider-gap verification", ""))
    lines.extend(("| classification | count |", "|---|---|"))
    for classification in CLASSIFICATIONS:
        lines.append(f"| {classification} | {validated_results['counts'][classification]} |")
    gap_rows = _gap_display_rows(validated_results, projection, actionable_only=True)
    if gap_rows:
        lines.extend(
            (
                "",
                "| target | field | classification | reason |",
                "|---|---|---|---|",
            )
        )
        for target, field, classification, reason in gap_rows:
            lines.append(f"| `{target}` | `{field}` | {classification} | `{reason}` |")
    else:
        lines.extend(("", "No actionable provider-gap findings."))

    if not tf_rows and not inventory_actionable and not gap_rows:
        lines.extend(
            (
                "",
                "Infrastructure matches the declared Terraform, inventory, and provider-gap configuration.",
            )
        )
    return "\n".join(lines) + "\n"


def render_report(
    plan: dict[str, Any],
    projection: dict[str, Any],
    results: dict[str, Any],
    *,
    is_organization: bool,
    owner: str,
    metadata_status_path: str | Path = "inventory-metadata.status",
    metadata_path: str | Path = "inventory-metadata.json",
) -> str:
    projection = validate_desired_state(projection)
    if projection["github_owner"] != owner or projection["github_is_organization"] != is_organization:
        raise ContractError("workflow owner does not match projection")
    redactions = private_redaction_set(plan, projection)
    tf_rows = terraform_rows(plan, redactions)
    validated_results = validate_results(results, projection)
    gap_rows = _gap_display_rows(validated_results, projection, actionable_only=True)

    check_messages: list[str] = []
    inventory_undeclared = False
    inventory_unverified = False
    if is_organization:
        check_status, check_messages = inventory_check(plan)
        enumeration_status = inventory_enumeration(
            plan,
            owner=owner,
            metadata_status_path=metadata_status_path,
            metadata_path=metadata_path,
        )
        inventory_undeclared = check_status == "fail"
        inventory_unverified = check_status == "unverified" or enumeration_status == "unverified"

    if not tf_rows and not inventory_undeclared and not inventory_unverified and not gap_rows:
        return ""

    lines: list[str] = []
    classes = Counter(classification for _, classification, _ in tf_rows)
    if classes["DRIFT / live-mismatch"]:
        lines.append(
            "DRIFT / live-mismatch: the live configuration no longer matches what Terraform declares."
        )
    if classes["INDETERMINATE / state-binding-missing"]:
        lines.append(
            "INDETERMINATE / state-binding-missing: Terraform has a desired resource with no canonical state binding; its live status is unproven."
        )
    lines.extend(("", "#### Terraform resource changes", ""))
    if not tf_rows:
        lines.append("No actionable Terraform resource changes.")
    else:
        tally = Counter("-".join(actions) for _, _, actions in tf_rows)
        lines.extend(("| count | action |", "|---|---|"))
        for action, count in sorted(tally.items(), key=lambda item: (-item[1], item[0])):
            lines.append(f"| {count} | `{action}` |")
        lines.extend(("", "| resource | class | action |", "|---|---|---|"))
        for address, classification, actions in sorted(tf_rows):
            lines.append(f"| `{address}` | {classification} | `{'-'.join(actions)}` |")
        if classes["DRIFT / live-mismatch"]:
            lines.extend(
                (
                    "",
                    "A `delete`, `update`, or replacement here means live GitHub no longer",
                    "matches the declared configuration. Re-applying restores the declaration.",
                )
            )
        if classes["INDETERMINATE / state-binding-missing"]:
            lines.extend(
                (
                    "A `create` here is a state-binding gap, not proof that the live object is absent.",
                )
            )
    if inventory_undeclared:
        lines.extend(("", "INVENTORY / undeclared-live:"))
        lines.extend(check_messages)
    if inventory_unverified:
        lines.extend(("", f"INVENTORY / enumeration-unverified: {INVENTORY_UNVERIFIED}"))
    if gap_rows:
        lines.extend(
            (
                "",
                "#### Provider-gap findings",
                "",
                "| target | field | classification | reason |",
                "|---|---|---|---|",
            )
        )
        for target, field, classification, reason in gap_rows:
            lines.append(f"| `{target}` | `{field}` | {classification} | `{reason}` |")
    return "\n".join(lines).strip() + "\n"


def _environment_bool(name: str, *, default: bool | None = None) -> bool:
    value = os.environ.get(name)
    if value is None and default is not None:
        return default
    if value not in ("true", "false"):
        raise ContractError("invalid workflow boolean")
    return value == "true"


def _load_render_inputs(detector: bool) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any] | None]:
    plan = load_plan("plan.json")
    projection = validate_desired_state(load_json_strict("provider-gap-desired-state.json"))
    results = load_results("provider-gap-results.json", projection) if detector else None
    return plan, projection, results


def _command_verify(args: argparse.Namespace) -> int:
    status = run_verifier(args.desired_state, args.results)
    print(f"provider-gap verification completed with status {status}")
    return status


def _command_summary(_args: argparse.Namespace) -> int:
    detector = _environment_bool("DETECTOR_MODE")
    is_organization = _environment_bool("TF_VAR_github_is_organization")
    owner = os.environ.get("TF_VAR_github_owner", "")
    plan, projection, results = _load_render_inputs(detector)
    sys.stdout.write(
        render_summary(
            plan,
            projection,
            results,
            detector=detector,
            is_organization=is_organization,
            owner=owner,
        )
    )
    return 0


def _command_report(_args: argparse.Namespace) -> int:
    is_organization = _environment_bool("TF_VAR_github_is_organization")
    owner = os.environ.get("TF_VAR_github_owner", "")
    plan, projection, results = _load_render_inputs(True)
    assert results is not None
    sys.stdout.write(
        render_report(
            plan,
            projection,
            results,
            is_organization=is_organization,
            owner=owner,
        )
    )
    return 0


def parser() -> argparse.ArgumentParser:
    command = argparse.ArgumentParser(description=__doc__)
    subcommands = command.add_subparsers(dest="command", required=True)
    verify = subcommands.add_parser("verify")
    verify.add_argument("--desired-state", default="provider-gap-desired-state.json")
    verify.add_argument("--results", default="provider-gap-results.json")
    verify.set_defaults(handler=_command_verify)
    summary = subcommands.add_parser("summary")
    summary.set_defaults(handler=_command_summary)
    report = subcommands.add_parser("report")
    report.set_defaults(handler=_command_report)
    return command


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        return int(args.handler(args))
    except Exception:
        print("::error::provider-gap projection failed safely", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
