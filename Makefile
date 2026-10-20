# BankOps — lệnh vận hành 1-click (thay cho chuỗi docker/flutter dài trong README).
# Chạy ở thư mục này: `make <target>`. Xem danh sách: `make help`.

.PHONY: help up down reset-demo logs ps test-backend analyze-backend test-frontend analyze-frontend build-frontend typecheck-worker check-secrets verify-e2e test-all check-all

help: ## Hiện danh sách lệnh
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Build + chạy toàn bộ stack (API :8000, Web :8080, PG :5432)
	docker compose up -d --build

down: ## Dừng stack (giữ dữ liệu demo)
	docker compose down

reset-demo: ## Reset demo về seed gốc (XOÁ HẾT dữ liệu demo hiện tại)
	docker compose down -v && docker compose up -d --build

logs: ## Xem log API + worker trực tiếp
	docker compose logs -f api worker

ps: ## Trạng thái container + healthcheck
	docker compose ps

test-backend: ## Chạy pytest với PostgreSQL tạm, cô lập hoàn toàn khỏi DB dev
	@set -e; \
	trap 'docker compose -p quanlykho-test -f "$(CURDIR)/docker-compose.test.yml" down -v --remove-orphans >/dev/null 2>&1 || true' EXIT; \
	docker compose -p quanlykho-test -f "$(CURDIR)/docker-compose.test.yml" up -d --wait; \
	cd backend && DATABASE_URL="postgresql+psycopg2://bankops:bankops@127.0.0.1:$${TEST_POSTGRES_PORT:-5433}/bankops_test" .venv/bin/python -m alembic upgrade head; \
	DATABASE_URL="postgresql+psycopg2://bankops:bankops@127.0.0.1:$${TEST_POSTGRES_PORT:-5433}/bankops_test" .venv/bin/python -m pytest tests -q

analyze-backend: ## Lint backend & ai bằng ruff
	python3 -m ruff check backend/ ai/

test-frontend: ## Chạy toàn bộ Flutter test (80 tests)
	cd frontend && flutter test --no-pub

analyze-frontend: ## Phân tích tĩnh code Flutter (flutter analyze)
	cd frontend && flutter analyze

build-frontend: ## Build Flutter Web release vào frontend/dist
	cd frontend && flutter build web --release && cp -rf build/web/* dist/

typecheck-worker: ## Kiểm tra TypeScript Cloudflare Worker
	cd infra/cloudflare-worker && npm run typecheck

check-secrets: ## Chặn credential phổ biến bị commit vào Git
	python3 scripts/check_no_secrets.py

verify-e2e: ## Chạy kiểm thử live E2E trên stack Docker đang chạy
	python3 backend/tests/verify_live_e2e.py

test-all: test-backend test-frontend ## Chạy toàn bộ test Backend + Frontend

check-all: check-secrets analyze-backend analyze-frontend typecheck-worker test-all ## Chạy toàn bộ guard, lint, typecheck và tests
