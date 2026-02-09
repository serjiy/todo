# syntax=docker/dockerfile:1

# ────────────────────────────────────────────────────────────────
# Стадия 1: сборка зависимостей
# ────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Устанавливаем зависимости сборки (для alpine нужно build-base, но slim достаточно)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ────────────────────────────────────────────────────────────────
# Стадия 2: финальный образ
# ────────────────────────────────────────────────────────────────
FROM python:3.12-slim

# Создаём не-root пользователя
RUN useradd -m appuser

WORKDIR /app

# Копируем только установленные пакеты
COPY --from=builder --chown=appuser:appuser /root/.local /home/appuser/.local

# Делаем pip-пакеты доступными
ENV PATH="/home/appuser/.local/bin:$PATH"

# Копируем код приложения (без мусора)
COPY --chown=appuser:appuser app.py .
COPY --chown=appuser:appuser templates ./templates
COPY --chown=appuser:appuser static ./static

USER appuser

EXPOSE 5000

# Production-ready сервер (gunicorn + gevent для асинхронности)
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "--worker-class", "gevent", "app:app"]