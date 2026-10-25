# syntax=docker/dockerfile:1

# 1. szakasz
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
COPY requirements.txt .
RUN pip install -r requirements.txt

# 2. szakasz
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

RUN useradd --create-home --uid 10001 appuser

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:appuser app.py .

# Számmal (UID), nem névvel: a Kubernetes runAsNonRoot ellenőrzése csak számból tudja
# eldönteni, hogy a felhasználó nem root; névvel a pod el sem indulna.
USER 10001
EXPOSE 8080

# Exec forma: a gunicorn lesz a PID 1, megkapja a SIGTERM-et (szép leállás)
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]