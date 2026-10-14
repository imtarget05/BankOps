"""Tích hợp model fine-tune BankOps vào HF Space (docs/17 mục 2b).

Bản fine-tune Qwen2.5-1.5B (GGUF Q4_K_M ~940 MB) không thể nằm trong repo
GitHub (giới hạn 100 MB/file) nên được upload thẳng vào repo Space; image nhúng
thư mục `model/` và ưu tiên GGUF fine-tune trước bản gốc tải từ HF Hub.

Các test dưới đây chỉ đọc file tĩnh trong `infra/hf-llm-space/` — không cần
Docker daemon hay truy cập mạng, chạy được trong CI hiện tại.
"""

from __future__ import annotations

import re
import stat
from pathlib import Path

import pytest
from conftest import REPO_DIR

SPACE_DIR = REPO_DIR / "infra" / "hf-llm-space"
MODEL_DIR = SPACE_DIR / "model"
BANKOPS_GGUF = "Qwen2.5-1.5B-Instruct.Q4_K_M.gguf"
GGUF_LIMIT_BYTES = 100 * 1024 * 1024  # giới hạn file của GitHub


def _dockerfile_text() -> str:
    dockerfile = SPACE_DIR / "Dockerfile"
    assert dockerfile.is_file(), "infra/hf-llm-space/Dockerfile phải tồn tại"
    return dockerfile.read_text()


def _entrypoint_text() -> str:
    entrypoint = SPACE_DIR / "entrypoint.sh"
    assert entrypoint.is_file(), "infra/hf-llm-space/entrypoint.sh phải tồn tại"
    return entrypoint.read_text()


class TestSpaceEntrypoint:
    def test_prefers_fine_tuned_gguf_over_base(self):
        """GGUF fine-tune phải được chọn trước GGUF gốc tải từ Hub."""
        text = _entrypoint_text()
        assert "BANKOPS_MODEL_FILE:-Qwen2.5-1.5B-Instruct.Q4_K_M.gguf" in text
        assert text.index(
            'IMAGE_MODEL="${BAKED_DIR}/${BANKOPS_MODEL_FILE}"'
        ) < text.index('${BAKED_DIR}/${MODEL_FILE}"')

    def test_fails_fast_without_any_gguf(self):
        assert "no model GGUF found" in _entrypoint_text()

    def test_passes_fine_tune_chat_template(self):
        """Chat template của bản fine-tune phải được truyền cho llama-server."""
        text = _entrypoint_text()
        assert "--chat-template" in text
        assert "chat_template.jinja" in text

    def test_replaces_stale_volume_model_by_size(self):
        """Model stale trên volume (đổi model rồi rebuild) phải bị thay bằng bản image."""
        assert "wc -c" in _entrypoint_text()

    def test_still_binds_port_7860(self):
        text = _entrypoint_text()
        assert '--port "${PORT}"' in text
        assert "--host 0.0.0.0" in text

    def test_no_secrets_in_entrypoint(self):
        assert not re.search(r"(?i)(hf_token|api_key|password)\s*=", _entrypoint_text())


class TestUploadScript:
    def test_script_exists_and_is_executable(self):
        script = REPO_DIR / "infra" / "scripts" / "upload-model-to-hf.sh"
        assert script.is_file(), "infra/scripts/upload-model-to-hf.sh phải tồn tại"
        assert script.stat().st_mode & stat.S_IXUSR, "script phải có quyền thực thi"

    def test_script_never_echoes_token(self):
        """Token chỉ nằm trong URL push (git tự che) — không bao giờ được in ra output."""
        script = (REPO_DIR / "infra" / "scripts" / "upload-model-to-hf.sh").read_text()
        assert "${HF_TOKEN}" in script, "script phải dùng HF_TOKEN từ môi trường"
        assert 'echo "${HF_TOKEN' not in script
        assert "echo ${HF_TOKEN" not in script

    def test_script_uploads_gguf_into_space_model_dir(self):
        script = (REPO_DIR / "infra" / "scripts" / "upload-model-to-hf.sh").read_text()
        assert 'repo_type="space"' in script
        assert 'path_in_repo=f"model/' in script

    def test_docs_reference_the_upload_script(self):
        docs = (REPO_DIR / "docs" / "17-hf-llm-space.md").read_text()
        assert "upload-model-to-hf.sh" in docs
        assert "## 2b." in docs


class TestZipIntegrationSources:
    """Đối chiếu artifact trong repo với nguồn từ zip tích hợp (nếu đang có trên máy)."""

    @pytest.mark.parametrize(
        ("archive_path", "repo_path"),
        [
            ("config.json", "config.json"),
            ("generation_config.json", "generation_config.json"),
            ("tokenizer.json", "tokenizer.json"),
            ("tokenizer_config.json", "tokenizer_config.json"),
            ("chat_template.jinja", "chat_template.jinja"),
        ],
    )
    def test_artifacts_match_zip_sources(self, archive_path: str, repo_path: str):
        extracted = Path("/tmp/bankops_integration") / archive_path
        if not extracted.is_file():
            pytest.skip(f"zip chưa giải nén tại {extracted}")
        assert (MODEL_DIR / repo_path).read_bytes() == extracted.read_bytes()


class TestSpaceArtifacts:
    def test_fine_tune_artifacts_are_committed(self):
        """Artifact tokenizer/config/chat-template của bản fine-tune phải nằm trong repo."""
        required = [
            "config.json",
            "generation_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "chat_template.jinja",
        ]
        missing = [name for name in required if not (MODEL_DIR / name).is_file()]
        assert not missing, f"thiếu artifact trong infra/hf-llm-space/model/: {missing}"

    def test_model_dir_contains_no_gguf_over_github_limit(self):
        """GGUF ~940MB không được commit vào GitHub (vượt giới hạn 100 MB/file)."""
        oversized = [
            path.name
            for path in MODEL_DIR.glob("*")
            if path.is_file() and path.stat().st_size > GGUF_LIMIT_BYTES
        ]
        assert not oversized, f"file vượt giới hạn 100 MB của GitHub: {oversized}"

    def test_model_artifacts_not_ignored_by_gitignore(self):
        """`.gitignore` gốc không được có mẫu rộng làm rơi artifact model/ khi commit."""
        lines = [
            line.strip()
            for line in (REPO_DIR / ".gitignore").read_text().splitlines()
            if line.strip() and not line.strip().startswith("#")
        ]
        for pattern in ("*.json", "*.jinja", "model/", "**/model/"):
            assert pattern not in lines, f".gitignore chứa mẫu dòng `{pattern}`"

    def test_space_gitattributes_keeps_lfs_rule_for_gguf(self):
        """Space giữ rule LFS cho *.gguf (phòng khi commit model vào repo Space bằng git)."""
        attrs = (SPACE_DIR / ".gitattributes").read_text()
        assert "*.gguf" in attrs and "lfs" in attrs


class TestSpaceDockerfile:
    def test_bakes_model_dir_into_image(self):
        """Image phải COPY thư mục model/ vào /app/models/bankops."""
        assert "COPY model/ /app/models/bankops/" in _dockerfile_text()

    def test_bakes_fine_tuned_gguf_name(self):
        assert BANKOPS_GGUF in _dockerfile_text()

    def test_base_image_still_pinned_by_digest(self):
        assert "@sha256:" in _dockerfile_text()

    def test_downloads_base_model_only_without_fine_tune(self):
        """Fallback tải bản gốc CHỈ khi model/ chưa có GGUF fine-tune."""
        text = _dockerfile_text()
        assert re.search(r"if \[ ! -s .*BANKOPS_MODEL_FILE", text), (
            "phải có điều kiện kiểm tra GGUF fine-tune trước khi tải bản gốc"
        )
        assert "huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}" in text

    def test_no_secrets_in_dockerfile(self):
        assert not re.search(r"(?i)(hf_token|api_key|password)\s*=", _dockerfile_text())
