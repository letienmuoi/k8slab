"""Orchestrate normalization, quality evaluation, and catalog persistence."""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


APP_VERSION = os.getenv("APP_VERSION", "dev")
PORT = int(os.getenv("PORT", "8080"))
NORMALIZER_URL = os.getenv("NORMALIZER_URL", "http://qnet-normalizer:8080").rstrip("/")
QUALITY_URL = os.getenv("QUALITY_URL", "http://qnet-quality:8080").rstrip("/")
CATALOG_URL = os.getenv("CATALOG_URL", "http://qnet-catalog:8080").rstrip("/")
PUBLIC_TOKEN = os.getenv("PUBLIC_API_TOKEN", "")
CATALOG_TOKEN = os.getenv("CATALOG_API_TOKEN", "")
MAX_RECORDS = int(os.getenv("MAX_RECORDS_PER_REQUEST", "500"))


def log(event: str, **fields: Any) -> None:
    print(json.dumps({"at": datetime.now(timezone.utc).isoformat(), "event": event, "service": "ingest", "version": APP_VERSION, **fields}, ensure_ascii=False), flush=True)


def call(url: str, body: Any, headers: dict[str, str] | None = None) -> tuple[int, Any]:
    request_headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), method="POST", headers=request_headers)
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as exc:
        try:
            payload = json.loads(exc.read().decode("utf-8"))
        except json.JSONDecodeError:
            payload = {"error": str(exc)}
        return exc.code, payload


def normalize_input(payload: Any) -> tuple[str, list[str]]:
    if not isinstance(payload, dict):
        raise ValueError("body must be a JSON object")
    dataset = str(payload.get("dataset", "")).strip()
    records = payload.get("records")
    if not dataset or len(dataset) > 100:
        raise ValueError("dataset is required and must be at most 100 characters")
    if not isinstance(records, list) or not records:
        raise ValueError("records must be a non-empty array")
    if len(records) > MAX_RECORDS:
        raise ValueError(f"records exceeds limit {MAX_RECORDS}")
    values: list[str] = []
    for item in records:
        if isinstance(item, dict):
            item = item.get("text", "")
        if not isinstance(item, str):
            raise ValueError("every record must be a string or an object containing text")
        values.append(item)
    return dataset, values


class Handler(BaseHTTPRequestHandler):
    server_version = "qnet-ingest"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def send_json(self, status: int, payload: Any) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health/live":
            self.send_json(200, {"status": "live", "service": "ingest", "version": APP_VERSION})
            return
        if self.path == "/health/ready":
            ready = all([NORMALIZER_URL, QUALITY_URL, CATALOG_URL, PUBLIC_TOKEN, CATALOG_TOKEN])
            self.send_json(200 if ready else 503, {"status": "ready" if ready else "not-ready"})
            return
        self.send_json(404, {"error": "route not found"})

    def do_POST(self) -> None:  # noqa: N802
        started = time.monotonic()
        if self.path != "/ingest":
            self.send_json(404, {"error": "route not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 2_097_152:
                raise ValueError("request body must be between 1 byte and 2 MiB")
            dataset, records = normalize_input(json.loads(self.rfile.read(length).decode("utf-8")))
            ingestion_id = str(uuid.uuid4())

            normalizer_status, normalizer = call(NORMALIZER_URL + "/normalize", {"records": records})
            if normalizer_status != 200:
                raise RuntimeError(f"normalizer returned {normalizer_status}: {normalizer}")
            normalized_records = [item["normalized"] for item in normalizer["items"]]

            quality_status, quality = call(
                QUALITY_URL + "/api/quality/evaluate",
                {"dataset": dataset, "records": normalized_records},
                {"X-API-Token": PUBLIC_TOKEN},
            )
            if quality_status != 200:
                raise RuntimeError(f"quality returned {quality_status}: {quality}")

            catalog_status, catalog = call(
                CATALOG_URL + "/datasets",
                {
                    "ingestion_id": ingestion_id,
                    "dataset": dataset,
                    "record_count": len(records),
                    "non_empty_count": quality["metrics"]["non_empty_records"],
                    "quality_score": quality["metrics"]["score"],
                    "quality_status": quality["status"],
                    "normalizer_version": normalizer["version"],
                },
                {"X-Catalog-Token": CATALOG_TOKEN},
            )
            if catalog_status != 201:
                raise RuntimeError(f"catalog returned {catalog_status}: {catalog}")

            result = {
                "ingestion_id": ingestion_id,
                "dataset": dataset,
                "normalized_records": normalized_records,
                "quality": quality,
                "catalog": catalog,
                "pipeline": {
                    "ingest_version": APP_VERSION,
                    "normalizer_version": normalizer["version"],
                    "duration_ms": round((time.monotonic() - started) * 1000, 2),
                },
            }
            log("dataset_ingested", ingestion_id=ingestion_id, dataset=dataset, records=len(records), score=quality["metrics"]["score"])
            self.send_json(201, result)
        except (ValueError, json.JSONDecodeError) as exc:
            log("ingestion_rejected", error=str(exc))
            self.send_json(400, {"error": str(exc)})
        except (OSError, RuntimeError) as exc:
            log("ingestion_failed", error=str(exc))
            self.send_json(502, {"error": str(exc)})


def main() -> None:
    log("service_started", port=PORT)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
