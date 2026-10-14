#!/usr/bin/env python3
"""Fail when tracked source files contain known BankOps secret formats.

This intentionally small guard catches the credential classes previously committed to
Compose. It scans only Git-tracked files so ignored developer secret files are neither
read nor printed. It is a complement to a managed secret scanner in CI, not a replacement.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PATTERNS = {
    "Cloudflare API token": re.compile(r"\bcfut_[A-Za-z0-9_-]{20,}\b"),
    "SMTP password assignment": re.compile(
        r"(?m)^\s*(?:-\s*)?SMTP_PASSWORD[ \t]*=[ \t]*(?![ \t]*(?:$|\$\{|<))[^\s#]+"
    ),
    "PEM private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
}


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [ROOT / name for name in result.stdout.decode().split("\0") if name]


def main() -> int:
    findings: list[str] = []
    for path in tracked_files():
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for label, pattern in PATTERNS.items():
            if pattern.search(text):
                findings.append(f"{path.relative_to(ROOT)}: {label}")

    if findings:
        print("Potential secret detected in tracked file(s):", file=sys.stderr)
        print("\n".join(findings), file=sys.stderr)
        return 1

    print("Secret guard passed: no known credential patterns in tracked files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
