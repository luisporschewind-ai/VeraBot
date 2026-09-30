# VeraBot 后端镜像（可选部署方式）。构建：docker compose build；运行：docker compose up -d
FROM python:3.12-slim
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /uvx /bin/
WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev
COPY verabot ./verabot
ENV PATH="/app/.venv/bin:$PATH" VERABOT_DATA_DIR=/app/data
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "verabot.main:app", "--host", "0.0.0.0", "--port", "8000"]
