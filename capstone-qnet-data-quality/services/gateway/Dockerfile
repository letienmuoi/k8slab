FROM python:3.13.5-alpine3.22

ARG APP_VERSION=1.0.0

RUN addgroup -S -g 10001 qnet \
    && adduser -S -D -H -u 10001 -G qnet qnet

WORKDIR /app
COPY app.py bootstrap.py tail_logs.py cluster_audit.py smoke_test.py network_probe.py /app/

ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080

USER 10001:10001
EXPOSE 8080

CMD ["python", "/app/app.py"]
