#!/usr/bin/env bash
# =============================================================================
# Quản Lý Kho Trà Sữa — Sync Secrets to GitHub Actions via GitHub CLI (gh)
#
# Reads from .env / .env.production and uploads secrets to GitHub Repository Secrets
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ENV_FILE="${ROOT_DIR}/.env.production"
if [ ! -f "${ENV_FILE}" ]; then
    ENV_FILE="${ROOT_DIR}/.env"
fi

if [ ! -f "${ENV_FILE}" ]; then
    error "No .env or .env.production found. Run scripts/setup_secrets_and_deploy.sh first."
fi

info "Reading secrets from ${ENV_FILE}..."
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

if ! command -v gh >/dev/null 2>&1; then
    warn "GitHub CLI (gh) is not installed on this machine."
    echo ""
    echo "To set secrets manually in GitHub:"
    echo "1. Go to: https://github.com/imtarget05/QuanLyKho/settings/secrets/actions"
    echo "2. Add the following Repository Secrets (paste each value BY HAND —"
    echo "   never echo the value into a terminal, a log or a commit):"
    # CHỈ in TÊN biến. TUYỆT ĐỐI không in giá trị: terminal/log/CI là nơi
    # secret bị lộ (xem docs/security/secret-rotation-inventory-2026-10-20.md §4).
    # Tên được ghi LITERAL (không nội suy biến) để không có đường nào in
    # giá trị secret ra stdout.
    echo "   - CLOUDFLARE_ACCOUNT_ID"
    echo "   - CLOUDFLARE_API_TOKEN"
    echo "   - CLOUDFLARE_TUNNEL_TOKEN"
    echo "   - DATABASE_URL"
    echo "   - AWS_ACCESS_KEY_ID"
    echo "   - AWS_SECRET_ACCESS_KEY"
    echo "   - BANKOPS_SIGNING_KEY"
    echo "   - BANKOPS_SESSION_SECRET"
    echo "   - SMTP_PASSWORD"
    echo "   - SUPERVISOR_PIN"
    echo "   - ALLOWED_ORIGINS"
    echo "   - AZURE_CLIENT_ID          (OIDC app registration client id)"
    echo "   - AZURE_TENANT_ID          (Entra ID tenant id)"
    echo "   - AZURE_SUBSCRIPTION_ID"
    echo "   - AZURE_RESOURCE_GROUP"
    echo "   - LANGFUSE_PUBLIC_KEY"
    echo "   - LANGFUSE_SECRET_KEY"
    echo "   - API_BASE_URL:          https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run"
    echo ""
    echo "   Legacy (DEPRECATED) — xoá, KHÔNG set lại:"
    echo "   - SECRET_KEY"
    exit 0
fi

info "Checking GitHub CLI authentication..."
if ! gh auth status >/dev/null 2>&1; then
    warn "GitHub CLI is not logged in. Run 'gh auth login' to authenticate."
    exit 1
fi

set_secret() {
    local key="$1"
    local val="$2"
    if [ -n "$val" ]; then
        echo -n "$val" | gh secret set "$key"
        success "Set GitHub secret: ${key}"
    else
        warn "Skipped ${key} (empty value)"
    fi
}

info "Syncing secrets to GitHub Repository..."
set_secret "CLOUDFLARE_ACCOUNT_ID" "${CLOUDFLARE_ACCOUNT_ID:-}"
set_secret "CLOUDFLARE_API_TOKEN" "${CLOUDFLARE_API_TOKEN:-}"
set_secret "CLOUDFLARE_TUNNEL_TOKEN" "${CLOUDFLARE_TUNNEL_TOKEN:-}"
set_secret "DATABASE_URL" "${DATABASE_URL:-}"
set_secret "AWS_ACCESS_KEY_ID" "${AWS_ACCESS_KEY_ID:-}"
set_secret "AWS_SECRET_ACCESS_KEY" "${AWS_SECRET_ACCESS_KEY:-}"
set_secret "API_BASE_URL" "https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run"
# Tên chuẩn (2026-10-21 rotation wave). Chỉ được sync khi biến có mặt trong
# env file; nếu không có -> "Skipped (empty value)" (không in giá trị).
set_secret "BANKOPS_SIGNING_KEY" "${BANKOPS_SIGNING_KEY:-}"
set_secret "BANKOPS_SESSION_SECRET" "${BANKOPS_SESSION_SECRET:-}"
set_secret "SMTP_PASSWORD" "${SMTP_PASSWORD:-}"
set_secret "SUPERVISOR_PIN" "${SUPERVISOR_PIN:-}"
set_secret "ALLOWED_ORIGINS" "${ALLOWED_ORIGINS:-}"
# Azure OIDC (thay cho azure/login dùng `creds` JSON cũ trong deploy.yml): 3
# giá trị định danh, KHÔNG phải client secret — federated credential cho issuer
# https://token.actions.githubusercontent.com.
set_secret "AZURE_CLIENT_ID" "${AZURE_CLIENT_ID:-}"
set_secret "AZURE_TENANT_ID" "${AZURE_TENANT_ID:-}"
set_secret "AZURE_SUBSCRIPTION_ID" "${AZURE_SUBSCRIPTION_ID:-}"
set_secret "AZURE_RESOURCE_GROUP" "${AZURE_RESOURCE_GROUP:-}"
# Serving observability (deploy.yml envVars LANGFUSE_*).
set_secret "LANGFUSE_PUBLIC_KEY" "${LANGFUSE_PUBLIC_KEY:-}"
set_secret "LANGFUSE_SECRET_KEY" "${LANGFUSE_SECRET_KEY:-}"
# `SECRET_KEY` (tên LEGACY/DEPRECATED) KHÔNG được sync nữa: 2 tên / 1 giá trị
# khiến rotate bị lệch, và `backend/entrypoint.sh` đã fail-fast ở production
# khi thiếu `BANKOPS_SIGNING_KEY`. Xoá secret cũ ở GitHub:
#   gh secret delete SECRET_KEY --repo imtarget05/QuanLyKho

echo ""
success "All available secrets successfully synchronized to GitHub Actions!"
