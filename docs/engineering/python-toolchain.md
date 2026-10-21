# Quyết định toolchain Python — Poetry là canonical

> **Trạng thái:** Đã chốt (2026-10-20) · **Phạm vi:** `backend/` (FastAPI + SQLAlchemy + Alembic)
> **Quyết định:** **Poetry 2.5.1** với lock file **`backend/poetry.lock`** là nguồn sự thật duy nhất
> cho dependency của backend. `uv` **KHÔNG** phải toolchain canonical.

## 1. Quyết định

| Hạng mục | Giá trị chốt |
|---|---|
| Trình quản lý dependency | **Poetry** (`pip install poetry poetry-plugin-export`) |
| Lock file canonical | **`backend/poetry.lock`** (được track trong git) |
| Manifest | `backend/pyproject.toml` — `[tool.poetry]` + `[tool.poetry.group.dev.dependencies]` |
| Build backend | `poetry.core.masonry.api` |
| Lệnh cài dependency (CI) | `poetry export -o requirements.txt --without-hashes --with dev` → `pip install -r requirements.txt` |
| Lệnh cài dependency (dev) | `poetry install --with dev` |
| Lệnh chạy (dev) | `poetry run pytest tests -q`, `poetry run alembic upgrade head` |
| `uv` | **không dùng để cài dependency backend**; `backend/uv.lock` là file rỗng (stub), bị `.gitignore` loại bỏ |

## 2. Bằng chứng — CI thật sự dùng gì

Nguồn: `.github/workflows/ci.yml`, job `test`:

```yaml
      - name: Install Poetry
        run: pip install poetry poetry-plugin-export
      - name: Install dependencies
        run: |
          cd backend
          poetry export -o requirements.txt --without-hashes --with dev
          pip install -r requirements.txt
```

→ CI **không** dùng `uv`: nó cài Poetry, export lock ra `requirements.txt` rồi `pip install`.

Các bằng chứng khác:

1. **`backend/pyproject.toml`** khai báo `[tool.poetry]`, `[tool.poetry.dependencies]`,
   `[tool.poetry.group.dev.dependencies]` và `build-backend = "poetry.core.masonry.api"`.
   Không có `[tool.uv]` và không có `[dependency-groups]` (PEP 735).
2. **`backend/poetry.lock` là lock thật**: `lock-version = 2.1`, sinh bởi Poetry 2.5.1,
   `content-hash` khớp `pyproject.toml` → `poetry check --lock` trả về rc=0.
3. **`backend/uv.lock` là stub**: chỉ 3 dòng header
   (`version = 1`, `revision = 3`, `requires-python = ">=3.11"`), **0 package**.
   `uv sync` với file này sẽ **không cài dependency nào**. Nó còn bị `.gitignore`
   (dòng `uv.lock`) loại khỏi git → **không phải** lock của repo.
4. **Tài liệu triển khai dùng Poetry**:
   `backend/README.md` (`poetry install`, `poetry run uvicorn ...`),
   `docs/14-cloudflare-deploy.md`, `docs/15-security-deploy-checklist.md`
   (`poetry run alembic upgrade head`, `poetry run pytest`).
5. **Môi trường dev cục bộ `backend/.venv`** không phải bằng chứng ngược lại: nó được
   tạo bằng `virtualenv` trên nền CPython do `uv` quản lý
   (`pyvenv.cfg` → `command = ... virtualenv ...`, `home = .../uv/python/cpython-3.11.15-...`),
   tức là `uv` chỉ cung cấp **interpreter**, không phải trình quản lý dependency.
   `Makefile::test-backend` chạy `backend/.venv/bin/python -m pytest` → không phụ thuộc
   trình cài nào.

## 3. Mâu thuẫn đã phát hiện (và cách xử lý)

| # | Mâu thuẫn | Mức độ | Xử lý |
|---|---|---|---|
| M1 | `backend/uv.lock` tồn tại (stub, 0 package) song song với `poetry.lock` | Trung bình | **Không xoá** (không thuộc phạm vi sửa của bước này; file untracked + gitignored). Ghi nhận tại đây là file KHÔNG dùng. Đề xuất: xoá file local này, hoặc thêm `backend/uv.lock` vào allowlist của `scripts/check_no_secrets.py`? Không cần. |
| M2 | `AGENTS.md` mục "Dev Commands" ghi `uv pip install -e backend` và stack ghi "Poetry/uv" | Thấp | **Đã sửa** trong bước này: hướng dẫn dùng `poetry install --with dev`, kèm link tài liệu này. |
| M3 | `backend/pyproject.toml` chưa dùng `[project]` (PEP 621) nên Poetry 2.x báo warning deprecation | Thấp | Không sửa (ngoài phạm vi; sẽ đụng `pyproject.toml`/`poetry.lock` của người khác). Warning là **không chặn** — `poetry check --lock` vẫn rc=0. |
| M4 | `poetry.lock` được tạo bởi Poetry 2.5.1 còn CI cài `poetry` không pin version | Thấp | Chưa đổi CI. Nếu muốn, bước sau có thể pin `poetry==2.5.1` để lock không drift. |

**Không có mâu thuẫn giữa CI và lock file**: CI dùng Poetry và `poetry.lock` là lock
đúng định dạng → **không cần sửa `.github/workflows/ci.yml`** ở bước này.

## 4. Quy trình cho contributor

```bash
cd backend

# 1. Cài môi trường (dùng đúng lock của repo)
poetry install --with dev
poetry run pytest tests -q

# 2. Thêm dependency -> SỬA pyproject.toml rồi cập nhật lock
poetry add httpx@^0.27.0            # thêm runtime dep
poetry add --group dev pytest-xdist # thêm dev dep
poetry lock --no-update             # chỉ cập nhật lock, KHÔNG nâng version đang pin

# 3. Kiểm tra lock còn khớp manifest
poetry check --lock
```

Luật:

- **KHÔNG** tạo/ commit `uv.lock` cho backend. `.gitignore` đã loại `uv.lock`.
- **KHÔNG** đổi trình quản lý dependency nếu chưa có quyết định mới trong
  `docs/engineering/` (thay thế tài liệu này).
- **KHÔNG** xoá `backend/poetry.lock`; nếu lock sai thì sửa `pyproject.toml` rồi
  `poetry lock` (không xoá tay).
- CI dùng `poetry export --with dev` → **dependency test/lint phải nằm trong group
  `dev`** (`[tool.poetry.group.dev.dependencies]`), nếu không CI sẽ chết với
  "pytest: command not found".

## 5. Kiểm chứng lại (2026-10-20)

```bash
$ cd backend
$ poetry --version
Poetry (version 2.5.1)

$ poetry check --lock; echo "rc=$?"
rc=0

$ poetry export -o /tmp/req_export_test.txt --without-hashes --with dev; echo "rc=$?"
rc=0
$ wc -l /tmp/req_export_test.txt
     133 /tmp/req_export_test.txt

$ grep -c '^\[\[package\]\]' uv.lock
0
```

## 6. Liên kết

- `.github/workflows/ci.yml` — job `test` (cài Poetry, export lock, chạy pytest + alembic).
- `backend/pyproject.toml` — manifest (`[tool.poetry]`, group `dev`).
- `backend/poetry.lock` — lock canonical.
- `backend/README.md`, `docs/14-cloudflare-deploy.md`, `docs/15-security-deploy-checklist.md` — hướng dẫn dùng `poetry`.
- `AGENTS.md` — mục "Dev Commands" (đã cập nhật theo quyết định này).
