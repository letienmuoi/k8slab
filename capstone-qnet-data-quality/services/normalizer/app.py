"""Unicode-aware text normalization bounded context."""

from __future__ import annotations

import json
import os
import re
import unicodedata
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


APP_VERSION = os.getenv("APP_VERSION", "dev")
PORT = int(os.getenv("PORT", "8080"))
WHITESPACE = re.compile(r"\s+")


def normalize(text: str, version: str = APP_VERSION) -> str:
    value = unicodedata.normalize("NFKC", text)
    if version.startswith("1.1"):
        value = "".join(
            " " if unicodedata.category(char).startswith("C") and char not in "\t\n\r" else char
            for char in value
            if unicodedata.category(char) != "Cf"
        )
    return WHITESPACE.sub(" ", value).strip().casefold()


def normalize_records(records: list[str]) -> list[dict[str, Any]]:
    return [
        {
            "original": record,
            "normalized": normalized,
            "character_count": len(normalized),
            "changed": record != normalized,
        }
        for record in records
        for normalized in [normalize(record)]
    ]


class Handler(BaseHTTPRequestHandler):
    server_version = "qnet-normalizer"

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
        if self.path == "/health/live" or self.path == "/health/ready":
            self.send_json(200, {"status": "ready", "service": "normalizer", "version": APP_VERSION})
        elif self.path == "/version":
            self.send_json(200, {"service": "normalizer", "version": APP_VERSION, "algorithm": "NFKC+trim+collapse+casefold"})
        else:
            self.send_json(404, {"error": "route not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/normalize":
            self.send_json(404, {"error": "route not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 2_097_152:
                raise ValueError("request body must be between 1 byte and 2 MiB")
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            records = payload.get("records")
            if records is None and isinstance(payload.get("text"), str):
                records = [payload["text"]]
            if not isinstance(records, list) or not all(isinstance(item, str) for item in records):
                raise ValueError("records must be an array of strings")
            if len(records) > 500:
                raise ValueError("at most 500 records are allowed")
            items = normalize_records(records)
            print(json.dumps({"at": datetime.now(timezone.utc).isoformat(), "event": "records_normalized", "service": "normalizer", "version": APP_VERSION, "count": len(items)}), flush=True)
            self.send_json(200, {"service": "normalizer", "version": APP_VERSION, "count": len(items), "items": items})
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": str(exc)})


if __name__ == "__main__":
    print(json.dumps({"event": "service_started", "service": "normalizer", "version": APP_VERSION, "port": PORT}), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
