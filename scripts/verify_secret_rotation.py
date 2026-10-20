#!/usr/bin/env python3
"""Post-rotation verification for the BankOps / QuanLyKho credential set.

The script is the *evidence gate* for the rotation wave: it proves, without ever
printing a secret value, that

* every credential has actually been replaced (its current fingerprint no longer
  matches the pre-rotation fingerprint recorded in the inventory), and
* the *old* credential is dead at the provider (old token revoked / old SMTP app
  password rejected), and
* no build artifact, log or test report still carries a secret value.

Design rules (hard):

* NEVER print a secret value. Only a *fingerprint* is ever printed:
  ``<4 first chars>…(len=<length>, sha256=<8 hex>)``.
* NEVER write a secret value to disk.
* Exit code ``0`` only when everything passed. ``1`` = at least one FAIL,
  ``2`` = inconclusive (missing input / network unreachable) -> also non-zero,
  because "no evidence" must never be reported as success.

Expected-fingerprint data is read from
``docs/security/secret-rotation-inventory-2026-10-20.md`` (machine-readable
JSON block). The owner fills in ``new_fingerprint`` there *after* rotating;
until that column is filled in, this tool reports "no evidence" and fails.

Usage::

    python3 scripts/verify_secret_rotation.py --check-env
    python3 scripts/verify_secret_rotation.py --check-provider
    python3 scripts/verify_secret_rotation.py --check-artifacts [DIR ...]
    python3 scripts/verify_secret_rotation.py --record-new [CRED_ID ...]
    python3 scripts/verify_secret_rotation.py --self-test
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import smtplib
import ssl
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Iterable

ROOT = Path(__file__).resolve().parents[1]
INVENTORY_PATH = ROOT / "docs/security/secret-rotation-inventory-2026-10-20.md"

EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_INCONCLUSIVE = 2

STATUS_PASS = "PASS"
STATUS_FAIL = "FAIL"
STATUS_SKIP = "SKIP"
STATUS_UNKNOWN = "UNKNOWN"


# --------------------------------------------------------------------------- #
# Fingerprint helpers
# --------------------------------------------------------------------------- #
def fingerprint(value: str) -> str:
    """``<4 first chars>…(len=<n>, sha256=<8 hex>)`` - never the value itself."""
    if not value:
        return "(empty)"
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:8]
    return f"{value[:4]}…(len={len(value)}, sha256={digest})"


def sha256_8(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:8]


def salted_fingerprint(cred_id: str, value: str) -> str | None:
    """Fingerprint for low-entropy credentials (e.g. a 6-digit PIN).

    A plain ``sha256[:8]`` of a 6-digit PIN is brute-forceable in microseconds,
    so publishing it would *be* publishing the PIN. For those credentials the
    owner records a **salted** hash instead; the salt lives outside the repo
    (env ``ROTATION_SALT_<CRED_ID>`` or ``ROTATION_FINGERPRINT_SALT``).
    Returns ``None`` when no salt is available -> the check is inconclusive.
    """
    salt = os.environ.get(f"ROTATION_SALT_{cred_id.upper()}") or os.environ.get(
        "ROTATION_FINGERPRINT_SALT"
    )
    if not salt:
        return None
    digest = hashlib.sha256((salt + value).encode("utf-8")).hexdigest()[:8]
    return f"salted(len={len(value)}, sha256={digest})"


# --------------------------------------------------------------------------- #
# Inventory loading
# --------------------------------------------------------------------------- #
_JSON_BLOCK_RE = re.compile(
    r"<!-- BEGIN INVENTORY-JSON -->\s*```json\s*(?P<body>.*?)\s*```\s*<!-- END INVENTORY-JSON -->",
    re.S,
)


def load_inventory(path: Path = INVENTORY_PATH) -> dict[str, Any]:
    if not path.is_file():
        raise SystemExit(
            f"[FATAL] Inventory not found: {path}\n"
            "        The rotation evidence gate cannot run without it."
        )
    text = path.read_text(encoding="utf-8")
    match = _JSON_BLOCK_RE.search(text)
    if not match:
        raise SystemExit(
            f"[FATAL] {path} does not contain the machine-readable "
            "'INVENTORY-JSON' block -> the evidence gate cannot run."
        )
    try:
        return json.loads(match.group("body"))
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive
        raise SystemExit(f"[FATAL] Inventory JSON block is invalid: {exc}") from exc


def credential_by_id(inventory: dict[str, Any], cred_id: str) -> dict[str, Any]:
    for cred in inventory.get("credentials", []):
        if cred.get("id") == cred_id:
            return cred
    raise SystemExit(f"[FATAL] Unknown credential id: {cred_id}")


# --------------------------------------------------------------------------- #
# Secret value readers (values stay in memory, are never printed)
# --------------------------------------------------------------------------- #
_ASSIGN_RE = re.compile(r"^\s*(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?P<value>.*?)\s*$")


def read_env_file(path: Path) -> dict[str, str]:
    """Parse a ``KEY=VALUE`` env file. Quoted values are unquoted."""
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        match = _ASSIGN_RE.match(line)
        if not match:
            continue
        value = match.group("value")
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        values[match.group("key")] = value
    return values


def read_k8s_string_data(path: Path) -> dict[str, str]:
    """Read ``stringData:`` of a Kubernetes Secret manifest (no yaml dependency)."""
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    in_block = False
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if re.match(r"^\s*stringData:\s*$", line):
            in_block = True
            continue
        if in_block:
            if line.strip() and not line.startswith((" ", "\t")):
                break
            match = re.match(r"^\s+(?P<key>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?P<value>.*?)\s*$", line)
            if match:
                value = match.group("value")
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                values[match.group("key")] = value
    return values


def location_values(loc: dict[str, Any]) -> tuple[str | None, str]:
    """Return ``(value, source_label)`` for one inventory location."""
    kind = loc.get("kind")
    if kind == "env_file":
        path = ROOT / loc["path"]
        values = read_env_file(path)
        return values.get(loc["key"]), f"{loc['path']}:{loc['key']}"
    if kind == "k8s_secret":
        path = ROOT / loc["path"]
        values = read_k8s_string_data(path)
        return values.get(loc["key"]), f"{Path(loc['path']).name}:{loc['key']}"
    if kind == "process_env":
        var = loc["var"]
        value = os.environ.get(var)
        if value is None:
            for legacy in loc.get("fallbacks", []):
                value = os.environ.get(legacy)
                if value is not None:
                    break
        return value, f"env:{var}"
    if kind == "github_secret":
        return None, f"gh-secret:{loc.get('name', '?')}"
    return None, f"{kind}:?"


# --------------------------------------------------------------------------- #
# --check-env
# --------------------------------------------------------------------------- #
def check_env(inventory: dict[str, Any]) -> tuple[int, list[str]]:
    lines: list[str] = []
    failures: list[str] = []
    inconclusive = 0

    lines.append("== --check-env : current value vs recorded fingerprints ==")
    lines.append(f"{'CREDENTIAL':<22}{'LOCATION':<56}{'CURRENT FINGERPRINT':<32}VERDICT")
    lines.append("-" * 150)

    for cred in inventory.get("credentials", []):
        cred_id = cred["id"]
        old_fp = cred.get("old_fingerprint")
        new_fp = cred.get("new_fingerprint")
        end_state = cred.get("end_state", "rotate")
        for loc in cred.get("locations", []):
            label = location_values(loc)[1]
            value, _ = location_values(loc)
            required = bool(loc.get("required"))
            if loc.get("kind") == "github_secret":
                lines.append(f"{cred_id:<22}{label:<56}{'(not locally verifiable)':<34}{STATUS_SKIP}")
                continue
            if value is None or value == "":
                if end_state == "remove":
                    verdict = STATUS_PASS
                    detail = "removed (legacy var absent)"
                elif required:
                    verdict = STATUS_FAIL
                    detail = "MISSING - required value not present"
                    failures.append(f"{cred_id} @ {label}: {detail}")
                else:
                    verdict = STATUS_SKIP
                    detail = "not set here"
                lines.append(f"{cred_id:<22}{label:<56}{'(absent)':<34}{verdict} - {detail}")
                continue

            current = fingerprint(value)
            mode_fp = current
            salted_mode = cred.get("fingerprint_mode") == "salted"
            if salted_mode:
                mode_fp = salted_fingerprint(cred_id, value)
                if mode_fp is None:
                    mode_fp = "<salted fingerprint unavailable>"
            if end_state == "remove":
                if current == old_fp:
                    verdict = STATUS_FAIL
                    detail = "legacy variable still holds the pre-rotation value"
                    failures.append(f"{cred_id} @ {label}: {detail}")
                else:
                    verdict = STATUS_FAIL
                    detail = "legacy variable still present - it must be removed"
                    failures.append(f"{cred_id} @ {label}: {detail}")
                lines.append(f"{cred_id:<22}{label:<56}{current:<34}{verdict} - {detail}")
                continue

            if old_fp and current == old_fp:
                verdict = STATUS_FAIL
                detail = "NOT ROTATED - still matches the pre-rotation value"
                failures.append(f"{cred_id} @ {label}: {detail}")
            elif new_fp and mode_fp == new_fp:
                verdict = STATUS_PASS
                detail = "matches the recorded post-rotation fingerprint"
            elif salted_mode and mode_fp == "<salted fingerprint unavailable>":
                verdict = STATUS_UNKNOWN
                detail = "salted fingerprint mode but no ROTATION_FINGERPRINT_SALT supplied"
                inconclusive += 1
            else:
                verdict = STATUS_FAIL
                detail = "value changed but NO post-rotation fingerprint recorded in the inventory"
                failures.append(f"{cred_id} @ {label}: {detail}")
            shown = current if verdict != STATUS_PASS else current
            lines.append(f"{cred_id:<22}{label:<56}{shown:<32}{verdict} - {detail}")

    lines.append("-" * 150)
    lines.append(
        "Legend: PASS = matches the fingerprint recorded after rotation | "
        "FAIL = still the old value / missing / no evidence recorded | "
        "SKIP = not present in this location (or not locally verifiable)"
    )
    if failures:
        lines.append("")
        lines.append(f"NOT ROTATED / MISSING EVIDENCE ({len(failures)}):")
        for item in failures:
            lines.append(f"  - {item}")
    else:
        lines.append("")
        lines.append("All inventoried credentials match their post-rotation fingerprints.")

    if inconclusive:
        return EXIT_INCONCLUSIVE, lines
    return (EXIT_FAIL if failures else EXIT_PASS), lines


# --------------------------------------------------------------------------- #
# --record-new
# --------------------------------------------------------------------------- #
def record_new(inventory: dict[str, Any], cred_ids: list[str]) -> tuple[int, list[str]]:
    lines = ["== --record-new : fingerprint of the CURRENT value (paste into the inventory) =="]
    lines.append("Only fingerprints are printed. Never paste secret values anywhere.")
    creds = inventory.get("credentials", [])
    if not cred_ids:
        creds = list(creds)
    for cred in creds:
        cred_id = cred["id"]
        if cred_ids and cred_id not in cred_ids:
            continue
        found = False
        for loc in cred.get("locations", []):
            value, label = location_values(loc)
            if not value:
                continue
            found = True
            if cred.get("fingerprint_mode") == "salted":
                mode_fp = salted_fingerprint(cred_id, value)
                if mode_fp is None:
                    lines.append(
                        f"{cred_id:<22}{label:<56}(set ROTATION_FINGERPRINT_SALT to compute a salted fingerprint)"
                    )
                    continue
                lines.append(f"{cred_id:<22}{label:<56}{mode_fp}")
            else:
                lines.append(f"{cred_id:<22}{label:<56}{fingerprint(value)}")
        if not found:
            lines.append(f"{cred_id:<22}{'(no value found locally)':<56}-")
    return EXIT_PASS, lines


# --------------------------------------------------------------------------- #
# --check-provider
# --------------------------------------------------------------------------- #
def _http_status(url: str, headers: dict[str, str], timeout: int = 20) -> tuple[int | None, str]:
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, ""
    except urllib.error.HTTPError as exc:
        return exc.code, ""
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        return None, f"network error: {type(exc).__name__}"


def check_cloudflare(old_token: str, new_token: str | None) -> list[tuple[str, str, str]]:
    url = "https://api.cloudflare.com/client/v4/user/tokens/verify"
    results: list[tuple[str, str, str]] = []
    status, err = _http_status(url, {"Authorization": f"Bearer {old_token}"})
    if status is None:
        results.append(("cloudflare_api_token", STATUS_UNKNOWN, f"old token check inconclusive ({err})"))
    elif status == 200:
        results.append(("cloudflare_api_token", STATUS_FAIL, f"old token still valid (HTTP {status}) - NOT revoked"))
    else:
        results.append(("cloudflare_api_token", STATUS_PASS, f"old token rejected (HTTP {status}) - revoked/dead"))
    if new_token:
        status, err = _http_status(url, {"Authorization": f"Bearer {new_token}"})
        if status is None:
            results.append(("cloudflare_api_token[NEW]", STATUS_UNKNOWN, f"new token check inconclusive ({err})"))
        elif status == 200:
            results.append(("cloudflare_api_token[NEW]", STATUS_PASS, f"new token accepted (HTTP {status})"))
        else:
            results.append(("cloudflare_api_token[NEW]", STATUS_FAIL, f"new token rejected (HTTP {status})"))
    else:
        results.append(("cloudflare_api_token[NEW]", STATUS_SKIP, "new token not supplied (CLOUDFLARE_NEW_TOKEN)"))
    return results


def check_smtp(old_password: str, new_password: str | None) -> list[tuple[str, str, str]]:
    host = os.environ.get("SMTP_HOST", "smtp.gmail.com")
    port = int(os.environ.get("SMTP_PORT", "587"))
    user = os.environ.get("SMTP_USER", "")
    results: list[tuple[str, str, str]] = []
    if not user:
        results.append(("smtp_password", STATUS_UNKNOWN, "SMTP_USER not set - cannot run the login probe"))
        return results

    def login(password: str) -> tuple[str, str]:
        try:
            with smtplib.SMTP(host, port, timeout=20) as client:
                client.starttls(context=ssl.create_default_context())
                client.login(user, password)
            return "OK", ""
        except smtplib.SMTPAuthenticationError as exc:
            return "AUTH_REJECTED", f"smtp code {exc.smtp_code}"
        except smtplib.SMTPResponseException as exc:
            return "AUTH_REJECTED", f"smtp code {exc.smtp_code}"
        except (smtplib.SMTPException, OSError) as exc:
            return "ERROR", f"{type(exc).__name__}"

    state, detail = login(old_password)
    if state == "AUTH_REJECTED":
        results.append(("smtp_password", STATUS_PASS, f"old app password rejected ({detail}) - dead"))
    elif state == "OK":
        results.append(("smtp_password", STATUS_FAIL, "old app password STILL LOGS IN - not revoked"))
    else:
        results.append(("smtp_password", STATUS_UNKNOWN, f"old app password check inconclusive ({detail})"))

    if new_password:
        state, detail = login(new_password)
        if state == "OK":
            results.append(("smtp_password[NEW]", STATUS_PASS, "new app password accepted"))
        elif state == "AUTH_REJECTED":
            results.append(("smtp_password[NEW]", STATUS_FAIL, f"new app password rejected ({detail})"))
        else:
            results.append(("smtp_password[NEW]", STATUS_UNKNOWN, f"new app password check inconclusive ({detail})"))
    else:
        results.append(("smtp_password[NEW]", STATUS_SKIP, "new app password not supplied (SMTP_NEW_PASSWORD)"))
    return results


def check_api_rejection(base_url: str, old_token: str, new_token: str | None) -> list[tuple[str, str, str]]:
    url = base_url.rstrip("/") + "/api/v1/auth/me"
    results: list[tuple[str, str, str]] = []
    status, err = _http_status(url, {"Authorization": f"Bearer {old_token}"})
    if status is None:
        results.append(("jwt_signing_key", STATUS_UNKNOWN, f"old token check inconclusive ({err})"))
    elif status in (401, 403):
        results.append(("jwt_signing_key", STATUS_PASS, f"old access token rejected (HTTP {status}) - signing key rotated"))
    else:
        results.append(("jwt_signing_key", STATUS_FAIL, f"old access token still accepted (HTTP {status})"))
    if new_token:
        status, err = _http_status(url, {"Authorization": f"Bearer {new_token}"})
        if status is None:
            results.append(("jwt_signing_key[NEW]", STATUS_UNKNOWN, f"new token check inconclusive ({err})"))
        elif status == 200:
            results.append(("jwt_signing_key[NEW]", STATUS_PASS, f"new access token accepted (HTTP {status})"))
        else:
            results.append(("jwt_signing_key[NEW]", STATUS_FAIL, f"new access token rejected (HTTP {status})"))
    else:
        results.append(("jwt_signing_key[NEW]", STATUS_SKIP, "new access token not supplied (NEW_ACCESS_TOKEN)"))
    return results


def check_provider() -> tuple[int, list[str]]:
    lines = ["== --check-provider : read-only liveness probes =="]
    lines.append("No resource is created, no mail is sent. Only status codes are shown.")
    lines.append("")
    results: list[tuple[str, str, str]] = []

    old_cf = os.environ.get("CLOUDFLARE_OLD_TOKEN")
    new_cf = os.environ.get("CLOUDFLARE_NEW_TOKEN")
    if old_cf:
        results.extend(check_cloudflare(old_cf, new_cf))
    else:
        results.append(("cloudflare_api_token", STATUS_SKIP, "CLOUDFLARE_OLD_TOKEN not supplied - old token NOT proven dead"))

    old_smtp = os.environ.get("SMTP_OLD_PASSWORD")
    new_smtp = os.environ.get("SMTP_NEW_PASSWORD")
    if old_smtp:
        results.extend(check_smtp(old_smtp, new_smtp))
    else:
        results.append(("smtp_password", STATUS_SKIP, "SMTP_OLD_PASSWORD not supplied - old app password NOT proven dead"))

    base_url = os.environ.get("API_BASE_URL")
    old_jwt = os.environ.get("OLD_ACCESS_TOKEN")
    new_jwt = os.environ.get("NEW_ACCESS_TOKEN")
    if base_url and old_jwt:
        results.extend(check_api_rejection(base_url, old_jwt, new_jwt))
    else:
        results.append(
            (
                "jwt_signing_key",
                STATUS_SKIP,
                "API_BASE_URL + OLD_ACCESS_TOKEN not supplied - old signing key NOT proven dead",
            )
        )

    lines.append(f"{'CHECK':<28}{'STATUS':<10}DETAIL")
    lines.append("-" * 110)
    for name, status, detail in results:
        lines.append(f"{name:<28}{status:<10}{detail}")
    lines.append("-" * 110)

    failed = [r for r in results if r[1] == STATUS_FAIL]
    unknown = [r for r in results if r[1] in (STATUS_SKIP, STATUS_UNKNOWN)]
    if failed:
        lines.append("")
        lines.append(f"PROVIDER CHECK FAILED ({len(failed)}):")
        for name, _status, detail in failed:
            lines.append(f"  - {name}: {detail}")
    if unknown:
        lines.append("")
        lines.append(f"INCONCLUSIVE ({len(unknown)}) - no evidence that the old credential is dead:")
        for name, _status, detail in unknown:
            lines.append(f"  - {name}: {detail}")
    if not failed and not unknown:
        lines.append("")
        lines.append("Every probed old credential is dead and every new credential works.")
        return EXIT_PASS, lines
    if failed:
        return EXIT_FAIL, lines
    return EXIT_INCONCLUSIVE, lines


# --------------------------------------------------------------------------- #
# --check-artifacts
# --------------------------------------------------------------------------- #
DEFAULT_ARTIFACT_DIRS = (
    "logs",
    "artifacts",
    "test-results",
    "backend/test-results",
    "backend/logs",
    "reports",
    "mlruns",
    "backend/.pytest_cache",
)

_TOKEN_RE = re.compile(r"[A-Za-z0-9_\-./+=]{8,}")


def _candidate_tokens(line: str) -> list[str]:
    """Candidate secret substrings of one line (never printed, only hashed)."""
    candidates: list[str] = []
    for word in line.split():
        cleaned = word.strip("\"'`;,()[]{}<>")
        if len(cleaned) >= 8:
            candidates.append(cleaned)
        for separator in ("=", ":"):
            if separator in cleaned:
                tail = cleaned.split(separator, 1)[1].strip("\"'`;,()[]{}<>")
                if len(tail) >= 8:
                    candidates.append(tail)
    for match in _TOKEN_RE.finditer(line):
        token = match.group(0)
        if len(token) >= 8:
            candidates.append(token)
    return candidates


def _known_secret_hashes(inventory: dict[str, Any]) -> dict[str, str]:
    """sha256[:8] -> credential id, for every secret value we can currently see."""
    hashes: dict[str, str] = {}
    for cred in inventory.get("credentials", []):
        cred_id = cred["id"]
        for loc in cred.get("locations", []):
            value, _ = location_values(loc)
            if value:
                hashes[sha256_8(value)] = cred_id
        # Optional: the owner can supply the *pre-rotation* value at runtime so
        # artifacts that captured the old secret are detected too.
        override = os.environ.get(f"OLD_SECRET_{cred_id.upper()}")
        if override:
            hashes[sha256_8(override)] = f"{cred_id}(old)"
    return hashes


def check_artifacts(
    inventory: dict[str, Any], paths: Iterable[str]
) -> tuple[int, list[str]]:
    lines = ["== --check-artifacts : do logs/artifacts still contain a secret value? =="]
    hashes = _known_secret_hashes(inventory)
    if not hashes:
        lines.append("No secret values available locally to compare against (nothing scanned).")
        return EXIT_INCONCLUSIVE, lines

    targets: list[Path] = []
    if paths:
        for raw in paths:
            path = Path(raw)
            if not path.is_absolute():
                path = ROOT / path
            targets.append(path)
    else:
        for raw in DEFAULT_ARTIFACT_DIRS:
            path = ROOT / raw
            if path.exists():
                targets.append(path)
    if not targets:
        lines.append("No artifact directory present to scan -> nothing to prove.")
        return EXIT_INCONCLUSIVE, lines

    findings: list[str] = []
    scanned = 0
    for target in targets:
        files = [target] if target.is_file() else [p for p in sorted(target.rglob("*")) if p.is_file()]
        for path in files:
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            scanned += 1
            for number, line in enumerate(text.splitlines(), start=1):
                for token in _candidate_tokens(line):
                    cred_id = hashes.get(sha256_8(token))
                    if cred_id:
                        try:
                            rel = str(path.relative_to(ROOT))
                        except ValueError:
                            rel = str(path)
                        findings.append(f"{rel}:{number}: secret value of '{cred_id}' found in artifact")
    lines.append(f"Scanned {scanned} file(s) under {len(targets)} target(s).")
    lines.append("")
    if findings:
        lines.append(f"FAIL - secret material found in artifacts ({len(findings)}):")
        for item in findings:
            lines.append(f"  - {item}")
        return EXIT_FAIL, lines
    lines.append("PASS - no known secret value found in the scanned artifacts.")
    return EXIT_PASS, lines


# --------------------------------------------------------------------------- #
# --self-test (uses fake values only)
# --------------------------------------------------------------------------- #
def self_test() -> tuple[int, list[str]]:
    lines = ["== --self-test : internal checks with FAKE values =="]
    failures: list[str] = []

    if fingerprint("abcdefgh") != "abcd…(len=8, sha256=" + sha256_8("abcdefgh") + ")":
        failures.append("fingerprint() format mismatch")
    if fingerprint("") != "(empty)":
        failures.append("fingerprint() on empty value mismatch")
    if sha256_8("abc") != hashlib.sha256(b"abc").hexdigest()[:8]:
        failures.append("sha256_8() mismatch")

    text = "BANKOPS_SIGNING_KEY=0123456789abcdef0123456789abcdef\n"
    found = re.search(r"BANKOPS_SIGNING_KEY[ \t]*[:=][ \t]*(?P<v>\S+)", text)
    if not found or found.group("v") != "0123456789abcdef0123456789abcdef":
        failures.append("env line parser mismatch")
    else:
        tmp_env = Path("/tmp/opencode/selftest.env")
        tmp_env.parent.mkdir(parents=True, exist_ok=True)
        tmp_env.write_text(text, encoding="utf-8")
        values = read_env_file(tmp_env)
        if values.get("BANKOPS_SIGNING_KEY") != "0123456789abcdef0123456789abcdef":
            failures.append("read_env_file() mismatch")

    yaml_text = "stringData:\n  SECRET_KEY: \"abc\"\n  OTHER: xyz\n"
    tmp = Path("/tmp/opencode/selftest-secret.yaml")
    tmp.write_text(yaml_text, encoding="utf-8")
    data = read_k8s_string_data(tmp)
    if data.get("SECRET_KEY") != "abc" or data.get("OTHER") != "xyz":
        failures.append("read_k8s_string_data() mismatch")

    if not INVENTORY_PATH.is_file():
        failures.append(f"inventory missing: {INVENTORY_PATH}")
    else:
        try:
            inventory = load_inventory()
        except SystemExit as exc:
            failures.append(f"inventory load failed: {exc}")
            inventory = {"credentials": []}
        if not inventory.get("credentials"):
            failures.append("inventory has no credentials")
        for cred in inventory.get("credentials", []):
            for field in ("id", "canonical_var", "old_fingerprint", "locations"):
                if field not in cred:
                    failures.append(f"credential {cred.get('id')} misses field '{field}'")
            for loc in cred.get("locations", []):
                if loc.get("kind") not in ("env_file", "k8s_secret", "process_env", "github_secret"):
                    failures.append(f"credential {cred.get('id')} has unknown location kind {loc.get('kind')}")

    lines.append(f"{len(failures)} failure(s)")
    for item in failures:
        lines.append(f"  - {item}")
    return (EXIT_FAIL if failures else EXIT_PASS), lines


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Verify the credential rotation (fingerprints only, never values)."
    )
    parser.add_argument("--check-env", action="store_true", help="compare current values with the recorded fingerprints")
    parser.add_argument("--check-provider", action="store_true", help="read-only provider liveness probes for the old credentials")
    parser.add_argument("--check-artifacts", action="store_true", help="scan logs/artifacts for secret values")
    parser.add_argument("--artifacts-path", action="append", default=[], metavar="PATH", help="extra artifact path to scan")
    parser.add_argument("--record-new", nargs="*", default=None, metavar="CRED_ID", help="print the fingerprint of the current value(s) to paste into the inventory")
    parser.add_argument("--self-test", action="store_true", help="run internal checks with fake values")
    parser.add_argument("--inventory", default=str(INVENTORY_PATH), help="path to the rotation inventory")
    args = parser.parse_args(argv)

    if not any((args.check_env, args.check_provider, args.check_artifacts, args.record_new is not None, args.self_test)):
        parser.print_help()
        return EXIT_INCONCLUSIVE

    inventory = load_inventory(Path(args.inventory))
    exit_code = EXIT_PASS
    blocks: list[tuple[int, list[str]]] = []

    if args.self_test:
        blocks.append(self_test())
    if args.record_new is not None:
        blocks.append(record_new(inventory, list(args.record_new)))
    if args.check_env:
        blocks.append(check_env(inventory))
    if args.check_provider:
        blocks.append(check_provider())
    if args.check_artifacts:
        blocks.append(check_artifacts(inventory, args.artifacts_path))

    for code, lines in blocks:
        for line in lines:
            print(line)
        print("")
        if code == EXIT_FAIL:
            exit_code = EXIT_FAIL
        elif code == EXIT_INCONCLUSIVE and exit_code == EXIT_PASS:
            exit_code = EXIT_INCONCLUSIVE
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
