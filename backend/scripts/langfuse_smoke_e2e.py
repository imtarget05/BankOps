#!/usr/bin/env python3
"""E2E smoke test with live Langfuse Cloud / self-hosted instance.

Usage:
    LANGFUSE_PUBLIC_KEY=pk-lf-... LANGFUSE_SECRET_KEY=sk-lf-... \
    poetry run python scripts/langfuse_smoke_e2e.py
"""

from __future__ import annotations

import asyncio
import os
import sys
import time

from pydantic import SecretStr

from app.config import Settings
from app.core.observability import (
    flush_langfuse,
    get_langfuse_client,
    record_ai_generation,
    reset_client_for_testing,
)


async def main() -> int:
    pk = os.environ.get("LANGFUSE_PUBLIC_KEY", "").strip()
    sk = os.environ.get("LANGFUSE_SECRET_KEY", "").strip()
    host = os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com").strip()

    if not pk or not sk:
        print("[ERROR] Missing credentials.")
        print("Please export LANGFUSE_PUBLIC_KEY and LANGFUSE_SECRET_KEY before running this script.")
        print("Example:")
        print("  LANGFUSE_PUBLIC_KEY=pk-lf-... LANGFUSE_SECRET_KEY=sk-lf-... python scripts/langfuse_smoke_e2e.py")
        return 1

    print(f"Connecting to Langfuse host: {host} with public key: {pk[:8]}...")
    reset_client_for_testing()
    settings = Settings(
        database_url="sqlite://",
        langfuse_enabled=True,
        langfuse_public_key=pk,
        langfuse_secret_key=SecretStr(sk),
        langfuse_host=host,
    )

    client = get_langfuse_client(settings)
    if client is None:
        print("[ERROR] Failed to initialize Langfuse client.")
        return 1

    trace_id = f"smoke-quanlykho-{int(time.time())}"
    print(f"Generating live trace: {trace_id}")

    gen_id = record_ai_generation(
        name="ai.assess_request",
        model="deterministic-policy-v1",
        input_data={"request_id": trace_id, "kind": "adjustment"},
        output_data={
            "risk_level": "high",
            "risk_score": 82,
            "summary": "Smoke test từ QuanLyKho (AI Observability verification)",
        },
        metadata={
            "assessment_source": "heuristic_fallback",
            "provider": "heuristic",
            "test_run": True,
        },
        trace_id=trace_id,
        user_id="smoke_tester",
        latency_ms=4.25,
        settings=settings,
    )

    print("Flushing trace to Langfuse endpoint...")
    flush_langfuse(settings)

    project_url = f"{host.rstrip('/')}/project"
    print("\n[SUCCESS] Trace successfully queued & flushed!")
    print(f"  • Trace ID: {trace_id}")
    print(f"  • Generation ID: {gen_id}")
    print("  • User ID: smoke_tester")
    print(f"  • Target Dashboard: {project_url}")
    print("  (Note: Cloud ingestion typically indexes traces within 5-10 seconds)")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
