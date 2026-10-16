 # QA 01 — Environment Setup
 
 ## QA Branch
 Created: `qa-validation-20261014` from `main` HEAD `af2157b`
 
 ## QA Database
 - **Container**: `bankops-qa-db`
 - **Image**: `postgres:16-alpine`
 - **Port**: 5433 (avoids conflict with any local PG on 5432)
 - **Credentials**: `bankops:bankops` / DB: `bankops`
 - **Status**: Running, accepting connections
 
 ## Python Environment
 - **Python**: 3.14.7 (Homebrew)
 - **Packages installed**: fastapi 0.141.1, pytest 9.1.1, asyncpg 0.32.0, httpx 0.27.0, sqlalchemy 2.1.4, alembic 1.20.0
 - **PYTHONPATH**: `/Users/mainguyenbinhtan/Downloads/BankOps/backend`
 
 ## Migration Steps
 1. Start QA DB container on port 5433
 2. Run migrations:
    ```bash
    cd backend && DATABASE_URL="postgresql+psycopg2://bankops:bankops@localhost:5433/bankops" python3 -m alembic upgrade head
    ```
 3. Seed demo data:
    ```bash
    cd backend && DATABASE_URL="postgresql+asyncpg://bankops:bankops@localhost:5433/bankops" APP_ENV=demo python3 -c "from app.database import init_db; import asyncio; asyncio.run(init_db())"
    ```
 4. Verify health:
    ```bash
    curl http://localhost:5433/health/ready  # via app startup
    ```