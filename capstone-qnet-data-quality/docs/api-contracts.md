# API contracts

All bodies use `application/json`; health paths do not require authentication.

## Gateway

### `GET /`

Returns application identity, version, and available routes.

### `GET /api/status`

Requires `X-API-Token`. Calls readiness endpoints of all four downstream
services and returns `200 ready` or `503 degraded`.

### `POST /api/ingest`

Requires `X-API-Token`.

```json
{
  "dataset": "customers-2026-08",
  "records": ["  CUSTOMER 001 ", "ＣＵＳＴＯＭＥＲ 002", ""]
}
```

Returns HTTP 201 with normalized records, metrics, catalog ID, ingestion ID,
service versions, and duration.

### `POST /api/normalize`

Requires `X-API-Token`; proxy to normalizer.

### `POST /api/quality/evaluate`

Requires `X-API-Token`; proxy to quality. Ingress also routes this prefix
directly to quality.

### `GET /api/catalog`

Requires `X-API-Token`; gateway supplies the internal catalog token.

## Ingest

### `POST /ingest`

Internal API. Accepts 1–500 strings or objects containing a `text` field.
Rejects invalid dataset names and oversized bodies with HTTP 400. Downstream
failure returns HTTP 502 and does not claim success.

## Normalizer

### `POST /normalize`

```json
{"records": ["  QNET   DATA ", "ＡＩ READY"]}
```

```json
{
  "service": "normalizer",
  "version": "1.1.0",
  "count": 2,
  "items": [
    {"original": "  QNET   DATA ", "normalized": "qnet data", "character_count": 9, "changed": true}
  ]
}
```

### `GET /version`

Used to identify active blue/green release.

## Quality

### `POST /api/quality/evaluate`

Requires `X-API-Token`. Score is:

```text
60% completeness + 40% uniqueness
```

Status is `PASS` when score is at least the ConfigMap threshold; otherwise
`REVIEW`.

## Catalog

### `POST /datasets`

Requires `X-Catalog-Token`. Stores one immutable ingestion summary. Duplicate
`ingestion_id` returns HTTP 409.

### `GET /datasets`

Requires `X-Catalog-Token`; returns the latest 100 entries.

### `GET /datasets/{name}`

Requires `X-Catalog-Token`; returns history for one dataset.

## Health contract

Every long-running service exposes:

```text
GET /health/live
GET /health/ready
```

Gateway additionally has a startup probe on `/health/live`. Catalog readiness
executes a real SQLite query. Gateway readiness checks runtime configuration
and both required Secret values.
