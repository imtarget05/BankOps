FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir poetry

# Copy poetry files and install dependencies first (for caching)
COPY pyproject.toml poetry.lock* ./
RUN pip install --no-cache-dir poetry poetry-plugin-export && \
    poetry export -o requirements.txt --without-hashes && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app ./app
COPY alembic ./alembic
COPY alembic.ini ./alembic.ini
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

EXPOSE 8000

CMD ["./entrypoint.sh"]
