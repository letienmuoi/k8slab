"""Persistent dataset catalog backed by SQLite on a Kubernetes PVC."""

from __future__ import annotations

import hmac
import json
import os
import sqlite3
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote


APP_VERSION = os.getenv("APP_VERSION", "dev")
PORT = int(os.getenv("PORT", "8080"))
DATABASE_PATH = Path(os.getenv("DATABASE_PATH", "/data/catalog.db"))
CATALOG_TOKEN = os.getenv("CATALOG_API_TOKEN", "")


SCHEMA = """
CREATE TABLE IF NOT EXISTS dataset_ingestions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ingestion_id TEXT NOT NULL UNIQUE,
    dataset TEXT NOT NULL,
    record_count INTEGER NOT NULL,
    non_empty_count INTEGER NOT NULL,
    quality_score REAL NOT NULL,
    quality_status TEXT NOT NULL,
    normalizer_version TEXT NOT NULL,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dataset_created_at
ON dataset_ingestions(dataset, created_at DESC);
"""


def connect() -> sqlite3.Connection:
    connection = sqlite3.connect(DATABASE_PATH, timeout=10)
    connection.row_factory = sqlite3.Row
    return connection


def initialize() -> None:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)
    with connect() as connection:
        connection.executescript(SCHEMA)
        connection.execute("PRAGMA journal_mode=WAL")


def create_entry(payload: dict[str, Any]) -> dict[str, Any]:
    required = ["ingestion_id", "dataset", "record_count", "non_empty_count", "quality_score", "quality_status", "normalizer_version"]
    missing = [key for key in required if key not in payload]
    if missing:
        raise ValueError("missing fields: " + ", ".join(missing))
    created_at = datetime.now(timezone.utc).isoformat()
    values = (
        str(payload["ingestion_id"]),
        str(payload["dataset"])[:100],
        int(payload["record_count"]),
        int(payload["non_empty_count"]),
        float(payload["quality_score"]),
        str(payload["quality_status"]),
        str(payload["normalizer_version"]),
        created_at,
    )
    with connect() as connection:
        cursor = connection.execute(
            """INSERT INTO dataset_ingestions
               (ingestion_id, dataset, record_count, non_empty_count, quality_score,
                quality_status, normalizer_version, created_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            values,
        )
        entry_id = cursor.lastrowid
    return {"id": entry_id, "ingestion_id": values[0], "dataset": values[1], "created_at": created_at}


def list_entries(dataset: str | None = None) -> list[dict[str, Any]]:
    query = "SELECT * FROM dataset_ingestions"
    parameters: tuple[Any, ...] = ()
    if dataset:
        query += " WHERE dataset = ?"
        parameters = (dataset,)
    query += " ORDER BY id DESC LIMIT 100"
    with connect() as connection:
        return [dict(row) for row in connection.execute(query, parameters).fetchall()]


class Handler(BaseHTTPRequestHandler):
    server_version = "qnet-catalog"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def send_json(self, status: int, payload: Any) -> None:
        raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def authorized(self) -> bool:
        return bool(CATALOG_TOKEN) and hmac.compare_digest(self.headers.get("X-Catalog-Token", ""), CATALOG_TOKEN)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health/live":
            self.send_json(200, {"status": "live", "service": "catalog", "version": APP_VERSION})
            return
        if self.path == "/health/ready":
            try:
                with connect() as connection:
                    connection.execute("SELECT 1").fetchone()
                self.send_json(200, {"status": "ready", "database": str(DATABASE_PATH)})
            except sqlite3.Error as exc:
                self.send_json(503, {"status": "not-ready", "error": str(exc)})
            return
        if not self.authorized():
            self.send_json(401, {"error": "invalid or missing X-Catalog-Token"})
            return
        if self.path == "/datasets":
            items = list_entries()
            self.send_json(200, {"count": len(items), "items": items})
            return
        if self.path.startswith("/datasets/"):
            dataset = unquote(self.path.removeprefix("/datasets/"))
            items = list_entries(dataset)
            self.send_json(200, {"dataset": dataset, "count": len(items), "items": items})
            return
        self.send_json(404, {"error": "route not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/datasets":
            self.send_json(404, {"error": "route not found"})
            return
        if not self.authorized():
            self.send_json(401, {"error": "invalid or missing X-Catalog-Token"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 1_048_576:
                raise ValueError("request body must be between 1 byte and 1 MiB")
            entry = create_entry(json.loads(self.rfile.read(length).decode("utf-8")))
            print(json.dumps({"event": "catalog_entry_created", **entry}, ensure_ascii=False), flush=True)
            self.send_json(201, {"status": "stored", **entry})
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": str(exc)})
        except sqlite3.IntegrityError as exc:
            self.send_json(409, {"error": str(exc)})


if __name__ == "__main__":
    initialize()
    print(json.dumps({"event": "service_started", "service": "catalog", "version": APP_VERSION, "database": str(DATABASE_PATH), "port": PORT}), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
