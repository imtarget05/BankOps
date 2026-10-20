#!/usr/bin/env python3
"""Fail when tracked source files contain known BankOps secret formats.

This intentionally small guard catches the credential classes previously committed to
Compose/Git history. It scans Git-tracked files by default so ignored developer secret
files are neither read nor printed. It is a complement to a managed secret scanner in
CI, not a replacement.

Design rules (S10 containment):

* NEVER print a secret value. A finding carries only ``path:line`` + a label.
* Self-exclusion: the scanner never scans its own source (it contains the patterns).
* Two severities:
  - ``fail`` — a credential assignment / credential format; blocks CI.
  - ``warn`` — heuristic (e.g. a Postgres URL carrying a password) that is too noisy
    for the dev/demo database URLs this repo intentionally commits; reported only.

Usage::

    python3 scripts/check_no_secrets.py                # tracked files (CI gate)
    python3 scripts/check_no_secrets.py --local        # also report local secret files
    python3 scripts/check_no_secrets.py --strict-local # ... and fail on them
    python3 scripts/check_no_secrets.py --scan PATH    # scan an arbitrary path (fixtures)
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SELF = Path(__file__).resolve()
# The guard and its unit test necessarily contain credential-shaped literals
# (patterns and fixtures). They are excluded from the scan so the gate does not
# fail on its own test data.
SELF_EXCLUDED_RELATIVE: tuple[str, ...] = (
    "scripts/check_no_secrets.py",
    "backend/tests/test_check_no_secrets.py",
)

SEVERITY_FAIL = "fail"
SEVERITY_WARN = "warn"

# --- Credential formats -------------------------------------------------------
FORMAT_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("Cloudflare API token", re.compile(r"\bcfut_[A-Za-z0-9_\-]{20,}\b")),
    ("PEM private key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----")),
    ("GitHub personal access token", re.compile(r"\bghp_[A-Za-z0-9]{20,}\b")),
    ("GitHub OAuth token", re.compile(r"\bgho_[A-Za-z0-9]{20,}\b")),
    ("GitHub fine-grained PAT", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("Slack token", re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}\b")),
    ("AWS access key id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("AWS secret access key", re.compile(r"(?i)\baws_secret_access_key\b[^\n]{0,40}?[A-Za-z0-9/+=]{40}\b")),
    ("OpenAI-style API key", re.compile(r"\bsk-(?:proj-|ant-|or-)?[A-Za-z0-9_\-]{20,}\b")),
    ("Google API key", re.compile(r"\bAIza[0-9A-Za-z_\-]{35,}\b")),
    ("Stripe live secret key", re.compile(r"\bsk_live_[A-Za-z0-9]{16,}\b")),
    ("Twilio account SID auth token", re.compile(r"\bSK[0-9a-fA-F]{32}\b")),
)

# --- Assignments that only make sense with a hardcoded value -------------------
# Names are the secret-ish variable names this repo actually uses. The name must
# start the line (env/yaml/sh style) so prose in docs is not mistaken for config.
SENSITIVE_ASSIGNMENT_NAMES: tuple[str, ...] = (
    "SMTP_PASSWORD",
    "GMAIL_APP_PASSWORD",
    "SMTP_APP_PASSWORD",
    "SECRET_KEY",
    "JWT_SECRET",
    "BACKUP_GPG_PASSPHRASE",
    "CLOUDFLARE_API_TOKEN",
    "CLOUDFLARE_TUNNEL_TOKEN",
    "AWS_SECRET_ACCESS_KEY",
    "AWS_ACCESS_KEY_ID",
    "GOOGLE_CLIENT_SECRET",
    "NEXTAUTH_SECRET",
    "BANKOPS_SIGNING_KEY",
    "BANKOPS_SESSION_SECRET",
)

_ASSIGNMENT_RE = re.compile(
    r"(?m)^[ \t]*(?:[-*][ \t]*)?(?P<name>"
    + "|".join(SENSITIVE_ASSIGNMENT_NAMES)
    + r")(?P<sep>[ \t]*[:=][ \t]*)(?P<rest>[^\n]*)"
)

# BANKOPS_<ref>_signing_key / BANKOPS_SESSION_SECRET / JWT_SIGNING_KEY...
# Case-insensitive on purpose: the repo uses `BANKOPS_dev_signing_key` (lower
# snake ref) in some places and `BANKOPS_SIGNING_KEY` (upper) in others.
_SIGNING_ASSIGNMENT_RE = re.compile(
    r"(?im)^[ \t]*(?:[-*][ \t]*)?(?P<name>[A-Za-z0-9_]*"
    r"(?:signing_key|SESSION_SECRET|JWT_SIGNING_KEY[A-Za-z0-9_]*))"
    r"(?P<sep>[ \t]*[:=][ \t]*)(?P<rest>[^\n]*)"
)

# Supervisor PIN: numeric-or-alnum literal at end of line. The lookbehind keeps
# DEMO_SUPERVISOR_PIN (a documented demo constant) out of the results.
_PIN_RE = re.compile(
    r"(?im)^[ \t]*(?:[-*][ \t]*)?(?<![A-Za-z0-9_])supervisor_pin"
    r"[ \t]*[:=][ \t]*(?P<q>[\"']?)(?P<val>[A-Za-z0-9]{4,64})(?P=q)[ \t]*(?:#[^\n]*)?$"
)

# Heuristic only: a database URL with an inline password.
_DB_URL_RE = re.compile(
    r"postgres(?:ql)?(?:\+[A-Za-z0-9_]+)?://[^\s:/@]+:(?P<pw>[^\s@\"']{4,})@",
)

_PLACEHOLDER_PREFIXES = (
    "${",
    "$(",
    "$",
    "<",
    "{{",
    "%(",
    "changeme",
    "change_me",
    "change-me",
    "generate",
    "your",
    "replace",
    "placeholder",
    "example",
    "secretmanager",
    "set_me",
    "setme",
    "todo",
    "null",
    "none",
    "xxx",
    "***",
    "redacted",
    "masked",
)


@dataclass(frozen=True)
class Finding:
    """A secret-shaped thing found at ``path:line``. Never carries the value."""

    path: str
    line: int
    label: str
    severity: str

    def render(self) -> str:
        return f"{self.path}:{self.line}: {self.label}"


def _strip_value(raw: str) -> str:
    """Normalise the right-hand side of an assignment to a bare literal."""
    value = raw.split("#", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value.strip()


def _is_placeholder(value: str) -> bool:
    if not value:
        return True
    if value.startswith(("${", "$(", "$", "<", "{{", "%(")):
        return True
    # Code expressions (SecretStr(''), os.getenv(...), get_password_hash(...))
    # are not hardcoded secrets.
    if "(" in value:
        return True
    lowered = value.lower()
    return any(lowered.startswith(prefix) for prefix in _PLACEHOLDER_PREFIXES)


def _looks_random(value: str, min_len: int = 16) -> bool:
    """True for a literal that looks like key material (long, mixed, not a word)."""
    if len(value) < min_len:
        return False
    has_digit = any(ch.isdigit() for ch in value)
    has_alpha = any(ch.isalpha() for ch in value)
    return has_digit and has_alpha


def scan_text(text: str, path_label: str) -> list[Finding]:
    """Return findings for ``text``. Only path/line/label is retained."""
    findings: list[Finding] = []
    seen: set[tuple[int, str]] = set()

    def add(line: int, label: str, severity: str = SEVERITY_FAIL) -> None:
        key = (line, label)
        if key in seen:
            return
        seen.add(key)
        findings.append(Finding(path=path_label, line=line, label=label, severity=severity))

    for label, pattern in FORMAT_PATTERNS:
        for match in pattern.finditer(text):
            add(text[: match.start()].count("\n") + 1, label)

    for match in _ASSIGNMENT_RE.finditer(text):
        value = _strip_value(match.group("rest"))
        if _is_placeholder(value):
            continue
        name = match.group("name")
        if len(value) >= 16:
            # An explicitly sensitive variable name with a long literal is a
            # hardcoded credential regardless of its character mix.
            add(
                text[: match.start()].count("\n") + 1,
                f"hardcoded {name} assignment",
            )
            continue
        # Short values (e.g. an app password) are still worth flagging for the
        # names that must never be weak; keep the label explicit.
        if len(value) >= 6 and name in {
            "SMTP_PASSWORD",
            "GMAIL_APP_PASSWORD",
            "SMTP_APP_PASSWORD",
        }:
            add(
                text[: match.start()].count("\n") + 1,
                f"hardcoded {name} assignment",
            )

    for match in _SIGNING_ASSIGNMENT_RE.finditer(text):
        value = _strip_value(match.group("rest"))
        if _is_placeholder(value) or not _looks_random(value, min_len=16):
            continue
        add(
            text[: match.start()].count("\n") + 1,
            f"hardcoded {match.group('name')} assignment",
        )

    for match in _PIN_RE.finditer(text):
        add(
            text[: match.start()].count("\n") + 1,
            "hardcoded supervisor PIN assignment",
        )

    for match in _DB_URL_RE.finditer(text):
        add(
            text[: match.start()].count("\n") + 1,
            "database URL with inline password",
            SEVERITY_WARN,
        )

    return findings


def _iter_files(paths: list[Path]):
    for path in paths:
        try:
            if not path.is_file():
                continue
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        yield path, text


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [ROOT / name for name in result.stdout.decode().split("\0") if name]


# Tracked env files are allowed only when they are *examples* (placeholders only).
# A tracked `.env` / `.env.production` is a committed secret file -> always fail.
TRACKED_ENV_ALLOWLIST: frozenset[str] = frozenset(
    {".env.example", ".env.production.example", ".env.sample", ".env.template"}
)


def _is_forbidden_tracked_env(relative: str) -> bool:
    """True for a tracked file that must never carry real secrets."""
    name = relative.rsplit("/", 1)[-1]
    if name in TRACKED_ENV_ALLOWLIST:
        return False
    return name == ".env" or name.startswith(".env.")


def scan_tracked_env_files() -> list[Finding]:
    """Fail when a real environment file is committed to git."""
    findings: list[Finding] = []
    try:
        names = [str(p.relative_to(ROOT)) for p in tracked_files()]
    except ValueError:  # pragma: no cover - defensive
        names = []
    for relative in names:
        if _is_forbidden_tracked_env(relative):
            findings.append(
                Finding(
                    path=relative,
                    line=1,
                    label="tracked environment file (.env*) must not be committed",
                    severity=SEVERITY_FAIL,
                )
            )
    return findings


def scan_paths(paths: list[Path]) -> list[Finding]:
    """Scan arbitrary paths (used for fixtures / non-git trees)."""
    findings: list[Finding] = []
    files: list[Path] = []
    for path in paths:
        if path.is_dir():
            for child in sorted(path.rglob("*")):
                if child.is_file():
                    files.append(child)
        elif path.is_file():
            files.append(path)
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        try:
            relative = str(path.relative_to(ROOT))
        except ValueError:
            relative = str(path)
        for finding in scan_text(text, relative):
            findings.append(finding)
    return findings


def scan_tracked_files() -> list[Finding]:
    findings: list[Finding] = []
    findings.extend(scan_tracked_env_files())
    for path, text in _iter_files(tracked_files()):
        if path.resolve() == SELF:
            continue
        try:
            relative = str(path.relative_to(ROOT))
        except ValueError:
            relative = str(path)
        if relative in SELF_EXCLUDED_RELATIVE:
            continue
        for finding in scan_text(text, relative):
            findings.append(finding)
    return findings


def local_secret_files(roots: list[Path] | None = None) -> list[Path]:
    """Local (ignored) env files that may hold real credentials."""
    roots = roots or [ROOT]
    candidates: list[Path] = []
    for root in roots:
        for name in (".env", "backend/.env"):
            candidates.append(root / name)
        for path in sorted(root.glob(".env.*")):
            candidates.append(path)
        for path in sorted((root / "backend").glob(".env.*")):
            candidates.append(path)
    tracked = set()
    try:
        tracked = {p.resolve() for p in tracked_files()}
    except Exception:  # noqa: BLE001 - a broken git checkout must not crash the guard
        tracked = set()
    existing: list[Path] = []
    for path in candidates:
        try:
            if path.is_file() and path.resolve() not in tracked:
                existing.append(path)
        except OSError:
            continue
    return existing


def scan_local_secret_files(extra_roots: list[Path] | None = None) -> list[Finding]:
    findings: list[Finding] = []
    for path in local_secret_files(extra_roots):
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        try:
            label = str(path.relative_to(ROOT))
        except ValueError:
            label = str(path)
        for finding in scan_text(text, label):
            findings.append(finding)
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--local",
        action="store_true",
        help="also report local (ignored) env files that hold credentials",
    )
    parser.add_argument(
        "--strict-local",
        action="store_true",
        help="fail the run when local (ignored) env files hold credentials",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="list every heuristic warning instead of a summary count",
    )
    parser.add_argument(
        "--scan",
        action="append",
        default=[],
        metavar="PATH",
        help="scan an arbitrary file/directory instead of the tracked tree "
             "(used to prove the guard fails on a fixture)",
    )
    args = parser.parse_args(argv)

    if args.scan:
        findings = scan_paths([Path(p) for p in args.scan])
        failing = [f for f in findings if f.severity == SEVERITY_FAIL]
        warnings = [f for f in findings if f.severity == SEVERITY_WARN]
        if warnings and args.verbose:
            print("Heuristic secret warnings:", file=sys.stderr)
            for finding in warnings:
                print(finding.render(), file=sys.stderr)
        if failing:
            print("Potential secret detected:", file=sys.stderr)
            for finding in failing:
                print(finding.render(), file=sys.stderr)
            return 1
        print("Secret guard passed: no known credential patterns in scanned path(s).")
        return 0

    findings = scan_tracked_files()
    failing = [f for f in findings if f.severity == SEVERITY_FAIL]
    warnings = [f for f in findings if f.severity == SEVERITY_WARN]

    local_findings: list[Finding] = []
    if args.local or args.strict_local:
        local_findings = scan_local_secret_files()
        local_failing = [f for f in local_findings if f.severity == SEVERITY_FAIL]
    else:
        local_failing = []

    if warnings:
        if args.verbose:
            print("Heuristic secret warnings (tracked files):", file=sys.stderr)
            for finding in warnings:
                print(finding.render(), file=sys.stderr)
        else:
            print(
                f"Heuristic secret warnings: {len(warnings)} finding(s) "
                "(dev/demo database URLs with inline password) — use --verbose to list.",
                file=sys.stderr,
            )

    if local_findings:
        print("Local (untracked) secret files — rotate these, they are not in git:",
              file=sys.stderr)
        for finding in local_findings:
            print(finding.render(), file=sys.stderr)

    if failing:
        print("Potential secret detected in tracked file(s):", file=sys.stderr)
        for finding in failing:
            print(finding.render(), file=sys.stderr)
        return 1

    if local_failing and args.strict_local:
        print("Potential secret detected in local file(s):", file=sys.stderr)
        return 1

    print("Secret guard passed: no known credential patterns in tracked files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
