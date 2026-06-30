# syntax=docker/dockerfile:1.7
FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

ENV TZ=Asia/Shanghai \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    PATH="/app/.venv/bin:${PATH}" \
    BTB_SERVER_NAME=0.0.0.0 \
    GRADIO_SERVER_PORT=7860 \
    GRADIO_NUM_PORTS=100 \
    BTB_DOCKER=1

ARG PIP_INDEX_URL=https://pypi.org/simple

WORKDIR /app
ENV UV_INDEX_URL=${PIP_INDEX_URL}

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    fontconfig \
    fonts-wqy-microhei \
    fonts-wqy-zenhei \
    tzdata && \
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && \
    echo "${TZ}" > /etc/timezone && \
    fc-cache -f && \
    rm -rf /var/lib/apt/lists/*

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY . .

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev && \
    python - <<'PY'
import fastapi
import gradio
import jinja2
import starlette

print(
    "Resolved runtime versions:",
    {
        "gradio": gradio.__version__,
        "fastapi": fastapi.__version__,
        "starlette": starlette.__version__,
        "jinja2": jinja2.__version__,
    },
)
PY

EXPOSE 7860

CMD ["python", "main.py"]
