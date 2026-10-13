# BankOps — lệnh vận hành 1-click (thay cho chuỗi docker/flutter dài trong README).
# Chạy ở thư mục này: `make <target>`. Xem danh sách: `make help`.

.PHONY: help up down reset-demo logs ps test-backend analyze-backend

help: ## Hiện danh sách lệnh
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

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

test-backend: ## Chạy toàn bộ pytest backend (101 tests)
	cd backend && python -m pytest tests -q

analyze-backend: ## Lint backend bằng ruff
	cd backend && ruff check app tests
