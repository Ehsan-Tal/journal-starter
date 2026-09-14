FROM python:3.14-slim

COPY --from=docker.io/astral/uv:latest /uv /uvx /bin

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-install-project

COPY . .

RUN uv sync --frozen

EXPOSE 8000

CMD ["uv", "run", "uvicorn", "api.main:app", "--host","0.0.0.0", "--port", "8000"]
