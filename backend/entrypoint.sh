#!/bin/sh
set -e

# --- Secret JWT (fail-closed) --------------------------------------------
# `app/config.py` mặc định `APP_ENV=production`: server thiếu
# `BANKOPS_SIGNING_KEY` thì KHÔNG được khởi động (token ký bằng secret
# ephemeral sẽ hết hạn sau mỗi lần restart).
# Secret trong k8s/HF đang đặt tên legacy là `SECRET_KEY` -> dùng làm signing
# key khi chưa cấp `BANKOPS_SIGNING_KEY` riêng.
#
# LEGACY FALLBACK: `SECRET_KEY` là tên CŨ của secret deploy. Template
# (`infra/k8s/base/secret-template.yaml`) đã khai báo `BANKOPS_SIGNING_KEY`
# (tên đúng mà `app/config.py` đọc) -> deploy mới KHÔNG cần dựa vào shim này.
# Shim chỉ còn để cluster cũ (chưa cấp lại secret) khởi động được; sẽ bỏ được
# khi mọi secret đã đổi sang `BANKOPS_SIGNING_KEY`.
if [ -z "${BANKOPS_SIGNING_KEY:-}" ] && [ -n "${SECRET_KEY:-}" ]; then
    echo "[Entrypoint] BANKOPS_SIGNING_KEY chưa set -> dùng SECRET_KEY (LEGACY fallback: tên cũ của secret deploy)."
    BANKOPS_SIGNING_KEY="$SECRET_KEY"
    export BANKOPS_SIGNING_KEY
fi

# --- Migrations: FAIL FAST -----------------------------------------------
# Migration lỗi => KHÔNG được start server với schema cũ (app sẽ chạy nhưng
# mọi truy vấn vào bảng/cột chưa migrate sẽ vỡ lúc runtime, lúc đó mới lộ
# lỗi). `set -e` + `if ! ...` -> exit code khác 0 => container dừng, orchestrator
# rollback, không phục vụ người dùng với dữ liệu nửa vời.
if [ -n "${DATABASE_URL:-}" ]; then
    echo "[Entrypoint] Running database migrations (alembic upgrade head)..."
    if ! alembic upgrade head; then
        echo "[Entrypoint] FATAL: 'alembic upgrade head' thất bại -> DỪNG khởi động server (không chạy với schema cũ)." >&2
        exit 1
    fi
else
    echo "[Entrypoint] DATABASE_URL is not set. Skipping alembic upgrade head."
fi

# --- Reverse proxy --------------------------------------------------------
# Sau nginx/Cloudflare/Traefik, mọi request đến từ IP của proxy. uvicorn chỉ
# tin `X-Forwarded-For` khi IP peer nằm trong `--forwarded-allow-ips`; mặc định
# chỉ tin loopback. Deploy sau proxy thật thì set `FORWARDED_ALLOW_IPS` (IP/CIDR
# của proxy) để rate-limit theo IP client THẬT thay vì gộp tất cả vào 1 IP.
FORWARDED_ALLOW_IPS="${FORWARDED_ALLOW_IPS:-127.0.0.1}"

echo "[Entrypoint] Starting Uvicorn on 0.0.0.0:${PORT:-8000} (forwarded-allow-ips=${FORWARDED_ALLOW_IPS})..."
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --forwarded-allow-ips "$FORWARDED_ALLOW_IPS"
