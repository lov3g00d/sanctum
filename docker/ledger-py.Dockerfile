# nimbus-ledger (Python 3.12 / FastAPI on uvicorn) container image.
# Build from repo root: docker build -f docker/ledger-py.Dockerfile -t nimbus/ledger .
#
# Pin base image by digest in prod, e.g. python:3.12-slim@sha256:<digest>
# Resolve with: docker buildx imagetools inspect python:3.12-slim
#
# Runtime is python:3.12-slim (non-root), not distroless: distroless python is
# version-locked to Debian's interpreter (3.11 on debian12), so a 3.12 venv will
# not run on it, and the debian12 language images are no longer well maintained.

FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

RUN python -m venv /opt/venv

COPY app/ledger-py/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt


FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

RUN groupadd --gid 10001 nimbus \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin nimbus

WORKDIR /app

COPY --from=builder --chown=10001:10001 /opt/venv /opt/venv
COPY --chown=10001:10001 app/ledger-py/app ./app

EXPOSE 8000

USER 10001:10001

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/opt/venv/bin/python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz').status == 200 else 1)"]

ENTRYPOINT ["/opt/venv/bin/uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
