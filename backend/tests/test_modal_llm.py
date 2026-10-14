"""Tích hợp model fine-tune BankOps vào Modal (thay HF Space — infra/modal/README.md).

HF chặn tạo Docker Space trên hardware free (yêu cầu gói PRO) nên backend LLM
chuyển sang Modal Starter (miễn phí $30 credit/tháng, scale-to-zero). API vẫn
OpenAI-compatible nên Worker chỉ cần đổi `HF_LLM_BASE_URL` — fallback Workers
AI giữ nguyên (infra/cloudflare-worker/src/routes/ai.ts).

Các test dưới đây chỉ đọc file tĩnh trong `infra/modal/` — không cần cài Modal,
không cần Docker daemon hay truy cập mạng, chạy được trong CI hiện tại.
"""

from __future__ import annotations

import ast
import re
import stat
from pathlib import Path

import pytest
from conftest import REPO_DIR

MODAL_DIR = REPO_DIR / "infra" / "modal"
SCRIPT_PATH = REPO_DIR / "infra" / "scripts" / "upload-model-to-modal.sh"
BANKOPS_GGUF = "Qwen2.5-1.5B-Instruct.Q4_K_M.gguf"


def _modal_app_text() -> str:
    path = MODAL_DIR / "modal_app.py"
    assert path.is_file(), "infra/modal/modal_app.py phải tồn tại"
    return path.read_text()


def _server_text() -> str:
    path = MODAL_DIR / "bankops_llm_server.py"
    assert path.is_file(), "infra/modal/bankops_llm_server.py phải tồn tại"
    return path.read_text()


def _server_ast() -> ast.Module:
    """Parse source server — file không được import `modal` (chạy như subprocess)."""
    return ast.parse(_server_text())


class TestModalAppDefinition:
    def test_model_lives_on_volume_not_in_image(self):
        """GGUF 940MB phải nằm trên Volume — image nhỏ, cold start nhanh."""
        text = _modal_app_text()
        assert 'modal.Volume.from_name(VOLUME_NAME, create_if_missing=True)' in text
        assert 'VOLUME_NAME = "bankops-llm"' in text
        assert "volumes={VOLUME_DIR: volume}" in text
        assert ".add_local_dir(" not in text, "không được nhúng model vào image"
        assert ".add_local_file(" not in text

    def test_pins_llama_cpp_version_with_cpu_wheel_index(self):
        text = _modal_app_text()
        assert "llama-cpp-python==0.3.36" in text
        assert "abetlen.github.io/llama-cpp-python/whl/cpu/" in text

    def test_pins_fastapi_uvicorn_pydantic(self):
        text = _modal_app_text()
        assert "fastapi==0.143.0" in text
        assert "uvicorn==0.54.0" in text
        assert "pydantic==2.14.1" in text

    def test_scales_to_zero_and_caps_request_duration(self):
        text = _modal_app_text()
        assert "scaledown_window=SCALE_DOWN_SECONDS" in text
        assert "SCALE_DOWN_SECONDS = 15 * 60" in text
        assert "timeout=WEB_TIMEOUT_SECONDS" in text

    def test_resources_are_cpu_only(self):
        text = _modal_app_text()
        assert "cpu=CPU_CORES" in text
        assert "memory=MEMORY_MIB" in text
        assert not re.search(r"\bgpu\s*=", text), "CPU-only — không được cấu hình GPU"

    def test_web_server_binds_expected_port_and_host(self):
        text = _modal_app_text()
        assert "@modal.web_server(PORT, startup_timeout=120)" in text
        assert "PORT = 8000" in text
        assert '"--host",\n            "0.0.0.0",' in text

    def test_ships_server_module_into_image(self):
        assert '.add_local_python_source("bankops_llm_server")' in _modal_app_text()

    def test_concurrency_deduplicates_cold_starts(self):
        assert "@modal.concurrent(max_inputs=4)" in _modal_app_text()

    def test_upload_uses_client_side_batch_upload(self):
        """Upload GGUF phải chạy client-side (batch_upload) — file local không
        tồn tại trong container remote nên không thể copy từ function remote."""
        text = _modal_app_text()
        assert "batch_upload(force=True)" in text
        assert "batch.put_file(gguf, dest)" in text
        assert "upload_model.remote(" not in text

    def test_local_entrypoint_uploads_gguf(self):
        text = _modal_app_text()
        assert "@app.local_entrypoint()" in text
        assert "def main(gguf: str) -> None:" in text
        assert "os.path.isfile(gguf)" in text

    def test_no_secrets_in_modal_app(self):
        assert not re.search(r"(?i)(hf_token|api_key|password)\s*=", _modal_app_text())


class TestOpenAIServer:
    def test_exposes_openai_endpoints(self):
        text = _server_text()
        assert '@app.post("/v1/chat/completions")' in text
        assert '@app.get("/health")' in text

    def test_response_shape_matches_worker_contract(self):
        """Worker đọc `choices[0].message.content` (infra/cloudflare-worker/src/routes/ai.ts)."""
        text = _server_text()
        assert '"message"' in text
        assert '"content"' in text
        assert '"finish_reason"' in text

    def test_rejects_streaming_explicitly(self):
        text = _server_text()
        assert "if req.stream:" in text
        assert "chưa được hỗ trợ" in text

    def test_validates_request_schema_with_pydantic(self):
        classes = {
            node.name for node in ast.walk(_server_ast()) if isinstance(node, ast.ClassDef)
        }
        assert "ChatCompletionRequest" in classes
        assert "ChatMessage" in classes

    def test_does_not_download_model_from_internet(self):
        """Model chỉ được đọc từ volume — không fetch từ HF Hub lúc runtime."""
        text = _server_text()
        assert "huggingface.co" not in text
        assert "hf_hub_download" not in text

    def test_model_path_comes_from_volume_env(self):
        text = _server_text()
        assert 'os.environ.get("BANKOPS_GGUF_DIR", "/data/bankops-llm")' in text
        assert BANKOPS_GGUF in text

    def test_server_module_must_not_import_modal(self):
        """File này chạy như subprocess uvicorn — import modal sẽ chết trong container."""
        imported = set()
        for node in ast.walk(_server_ast()):
            if isinstance(node, ast.Import):
                imported.update(alias.name.split(".")[0] for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                imported.add(node.module.split(".")[0])
        assert "modal" not in imported

    def test_no_secrets_in_server(self):
        assert not re.search(r"(?i)(hf_token|api_key|password)\s*=", _server_text())


class TestUploadScript:
    def test_script_exists_and_is_executable(self):
        assert SCRIPT_PATH.is_file(), f"{SCRIPT_PATH} phải tồn tại"
        assert SCRIPT_PATH.stat().st_mode & stat.S_IXUSR, "script phải có quyền thực thi"

    def test_script_accepts_zip_or_gguf(self):
        text = SCRIPT_PATH.read_text()
        assert "*.zip)" in text
        assert "python3 -m zipfile -e" in text
        assert "modal run" in text

    def test_script_never_contains_a_token(self):
        text = SCRIPT_PATH.read_text()
        assert not re.search(r"hf_[A-Za-z0-9]{20,}", text), "token không được nằm trong script"
        assert "set -euo pipefail" in text

    def test_script_uses_expected_gguf_name(self):
        assert BANKOPS_GGUF in SCRIPT_PATH.read_text()


class TestDocsAndWorkerIntegration:
    def test_modal_readme_documents_setup_and_deploy(self):
        readme = (MODAL_DIR / "README.md").read_text()
        assert "modal deploy infra/modal/modal_app.py" in readme
        assert "upload-model-to-modal.sh" in readme
        assert "HF_LLM_BASE_URL" in readme

    def test_worker_env_var_comment_mentions_modal_fallback_path(self):
        """wrangler.toml phải dẫn hướng được khi HF Space không khả dụng."""
        wrangler = (REPO_DIR / "infra" / "cloudflare-worker" / "wrangler.toml").read_text()
        assert "HF_LLM_BASE_URL" in wrangler
        assert "Modal" in wrangler

    def test_gguf_name_consistent_with_zip_source(self):
        """Tên GGUF trong code phải khớp artifact fine-tune thật (nếu zip còn trên máy)."""
        extracted = Path("/tmp/bankops_integration") / BANKOPS_GGUF
        if not extracted.is_file():
            pytest.skip(f"zip chưa giải nén tại {extracted}")
        assert extracted.stat().st_size > 500 * 1024 * 1024, "GGUF fine-tune phải ~940 MB"
