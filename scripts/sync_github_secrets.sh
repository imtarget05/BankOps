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
    echo "1. Go to: https://github.com/imtarget05/BankOps/settings/secrets/actions"
    echo "2. Add the following Repository Secrets:"
    echo "   - CLOUDFLARE_ACCOUNT_ID: ${CLOUDFLARE_ACCOUNT_ID:-}"
    echo "   - CLOUDFLARE_API_TOKEN:  ${CLOUDFLARE_API_TOKEN:-}"
    echo "   - DATABASE_URL:          ${DATABASE_URL:-}"
    echo "   - SECRET_KEY:            ${SECRET_KEY:-}"
    echo "   - API_BASE_URL:          https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run"
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
set_secret "SECRET_KEY" "${SECRET_KEY:-}"
set_secret "AWS_ACCESS_KEY_ID" "${AWS_ACCESS_KEY_ID:-}"
set_secret "AWS_SECRET_ACCESS_KEY" "${AWS_SECRET_ACCESS_KEY:-}"
set_secret "API_BASE_URL" "https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run"

echo ""
success "All available secrets successfully synchronized to GitHub Actions!"
