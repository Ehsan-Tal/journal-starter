FROM python:3.14-slim

COPY --from=docker.io/astral/uv:latest /uv /uvx /bin/

WORKDIR /app

# Dependencies first: this layer stays cached until pyproject.toml / uv.lock change
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

# Application source (note: "COPY . ." with nothing after the second dot)
COPY . .
RUN uv sync --frozen

# Venv on PATH, so the container starts uvicorn directly instead of via "uv run"
ENV PATH="/app/.venv/bin:$PATH"

# Last on purpose: a new commit SHA then only invalidates these tiny layers
ARG GIT_COMMIT=unknown
ENV GIT_COMMIT=$GIT_COMMIT

EXPOSE 8000
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
