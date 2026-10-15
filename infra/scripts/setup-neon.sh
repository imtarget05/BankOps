#!/usr/bin/env bash
# =============================================================================
# Quản Lý Kho Trà Sữa — Script setup Neon PostgreSQL + Cloudflare
# =============================================================================
# Chạy: bash infra/scripts/setup-neon.sh
# Yêu cầu: psql, wrangler đã cài và đăng nhập Cloudflare
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/../../backend" && pwd)"

# ─── Màu sắc output ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Quản Lý Kho Trà Sữa — Cloudflare + Neon Setup Script   ║"
echo "║  Backend Modal + frontend Cloudflare Workers Assets       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── Kiểm tra tools ──────────────────────────────────────────────────────────
info "Kiểm tra dependencies..."
command -v psql     >/dev/null 2>&1 || error "psql chưa cài. brew install postgresql"
command -v wrangler >/dev/null 2>&1 || error "wrangler chưa cài. npm install -g wrangler"
command -v npm      >/dev/null 2>&1 || error "npm chưa cài."
success "Tất cả tools OK"

# ─── Nhập thông tin ──────────────────────────────────────────────────────────
echo ""
info "=== BƯỚC 1: Neon Database ==="
echo ""
echo "1. Vào https://console.neon.tech và tạo project cho Quản Lý Kho Trà Sữa"
echo "2. Lấy connection string dạng:"
echo "   postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/kho-tra-sua?sslmode=require"
echo ""
read -rp "Dán Neon connection string (pooled endpoint): " NEON_URL
[[ -z "$NEON_URL" ]] && error "Connection string không được trống"

# Validate format
if [[ ! "$NEON_URL" =~ ^postgresql:// ]]; then
  error "Connection string phải bắt đầu bằng postgresql://"
fi

# Chuyển sang asyncpg format cho Python (Alembic)
NEON_URL_ASYNC="${NEON_URL/postgresql:\/\//postgresql+asyncpg://}"

# ─── Test kết nối ─────────────────────────────────────────────────────────────
info "Test kết nối Neon..."
psql "$NEON_URL" -c "SELECT version();" >/dev/null 2>&1 || error "Không kết nối được Neon. Kiểm tra lại connection string."
success "Kết nối Neon OK"

# ─── Run migrations ──────────────────────────────────────────────────────────
echo ""
info "=== BƯỚC 2: Chạy Alembic migrations ==="
cd "$BACKEND_DIR"

# Kiểm tra poetry
if command -v poetry >/dev/null 2>&1; then
  PYTHON_RUN="poetry run"
else
  PYTHON_RUN=""
  warn "Poetry không có. Dùng python trực tiếp (cần venv đã setup)."
fi

DATABASE_URL="$NEON_URL_ASYNC" $PYTHON_RUN alembic upgrade head
success "Migrations hoàn tất"

# ─── Seed demo data ──────────────────────────────────────────────────────────
echo ""
info "=== BƯỚC 3: Seed demo data ==="
DATABASE_URL="$NEON_URL_ASYNC" $PYTHON_RUN python -c \
  "from app.seed import seed_demo; import asyncio; asyncio.run(seed_demo())"
success "Seed data hoàn tất"

# ─── Tạo JWT secret ──────────────────────────────────────────────────────────
echo ""
info "=== BƯỚC 4: Tạo JWT secret ==="
JWT_SECRET=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)
success "JWT secret generated (32 bytes hex)"

# ─── Cài npm Worker dependencies ─────────────────────────────────────────────
echo ""
info "=== BƯỚC 5: Install Worker dependencies ==="
WORKER_DIR="$(cd "$SCRIPT_DIR/../cloudflare-worker" && pwd)"
cd "$WORKER_DIR"
npm install
success "npm install OK"

# ─── Đặt Cloudflare secrets ──────────────────────────────────────────────────
echo ""
info "=== BƯỚC 6: Đặt secrets lên Cloudflare Workers ==="
cd "$WORKER_DIR"

echo "$NEON_URL"     | wrangler secret put DATABASE_URL   && success "DATABASE_URL set"
echo "$JWT_SECRET"   | wrangler secret put JWT_SECRET     && success "JWT_SECRET set"
echo "$SESSION_SECRET" | wrangler secret put SESSION_SECRET && success "SESSION_SECRET set"

# Google Client ID (public, không cần secret nhưng để Worker đọc được)
read -rp "Google Client ID (hoặc Enter để skip): " GOOGLE_CLIENT_ID
if [[ -n "$GOOGLE_CLIENT_ID" ]]; then
  echo "$GOOGLE_CLIENT_ID" | wrangler secret put GOOGLE_CLIENT_ID
  success "GOOGLE_CLIENT_ID set"
fi

# PIN duyệt giao dịch rủi ro cao — BẮT BUỘC cho production. PIN demo 123456
# chỉ được chấp nhận khi APP_ENV=demo; production phải dùng PIN riêng, mạnh.
read -rsp "SUPERVISOR_PIN?Nhập PIN production (ẩn): " SUPERVISOR_PIN
echo ""
if [[ -z "$SUPERVISOR_PIN" ]]; then
  error "SUPERVISOR_PIN không được để trống cho production"
fi
echo "$SUPERVISOR_PIN" | wrangler secret put SUPERVISOR_PIN && success "SUPERVISOR_PIN set"
unset SUPERVISOR_PIN

# ─── Deploy Worker ────────────────────────────────────────────────────────────
echo ""
info "=== BƯỚC 7: Deploy Cloudflare Worker ==="
npm run deploy
success "Worker deployed!"

# ─── Tóm tắt ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                    ✅ SETUP HOÀN TẤT                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "Web URL: https://quan-ly-kho-tra-sua.tanmainguyenbinh.workers.dev"
echo "API URL: https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run"
echo ""
echo "Bước tiếp theo:"
echo "  1. Build Flutter web:"
echo "     cd frontend"
echo "     flutter build web --release \\"
echo "       --dart-define=API_BASE_URL=https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run"
echo ""
echo "  2. Deploy Pages:"
echo "     cd frontend"
echo "     rsync -a --exclude='_redirects' build/web/ build/worker-assets/"
echo "     cp ../infra/cloudflare-pages/_headers build/worker-assets/_headers"
echo "     npx wrangler@4 deploy --config ../infra/cloudflare-worker/wrangler.tea-inventory.toml"
echo ""
echo "  3. Thêm secrets GitHub Actions:"
echo "     CLOUDFLARE_API_TOKEN  = <lấy từ dash.cloudflare.com → My Profile → API Tokens>"
echo "     CLOUDFLARE_ACCOUNT_ID = $(wrangler whoami 2>/dev/null | grep -oE '[a-f0-9]{32}' | head -1 || echo '<lấy từ dash.cloudflare.com>')"
echo "     API_BASE_URL          = https://imtarget05--quan-ly-kho-tra-sua-api.us-east.modal.run"
echo ""
