# syntax=docker/dockerfile:1.9

# ---------------------------------------------------------------------------
# Stage 1 — builder
#
# Resolves and installs dependencies into a self-contained virtualenv.
# uv is only needed here; it never reaches the runtime image.
# ---------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

# Copy only the dependency manifests first. Application source changes far more
# often than dependencies, so keeping them in separate layers means a normal
# code change reuses the cached dependency layer instead of reinstalling.
COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project

# ---------------------------------------------------------------------------
# Stage 2 — runtime
#
# Starts from a clean Python image and copies in only the virtualenv and the
# application source. No uv, no build tooling, no lockfiles.
# ---------------------------------------------------------------------------
FROM python:3.13-slim-bookworm AS runtime

# Run as an unprivileged user. If the application is ever compromised, the
# attacker lands as `app` rather than as root inside the container.
RUN groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid app --no-create-home app

WORKDIR /app

COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --chown=app:app src ./src

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

USER app

EXPOSE 8000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
