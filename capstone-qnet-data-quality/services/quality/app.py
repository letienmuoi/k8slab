"""Evaluate completeness and uniqueness of normalized datasets."""

from __future__ import annotations

import hmac
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


APP_VERSION = os.getenv("APP_VERSION", "dev")
PORT = int(os.getenv("PORT", "8080"))
THRESHOLD = float(os.getenv("QUALITY_THRESHOLD", "80"))
PUBLIC_TOKEN = os.getenv("PUBLIC_API_TOKEN", "")


def evaluate(records: list[str], threshold: float = THRESHOLD) -> dict[str, Any]:
    if not records:
        raise ValueError("records must not be empty")
    cleaned = [record.strip() for record in records]
    non_empty = [record for record in cleaned if record]
    total = len(cleaned)
    completeness = len(non_empty) / total
    uniqueness = len(set(non_empty)) / len(non_empty) if non_empty else 0.0
    score = round((completeness * 0.6 + uniqueness * 0.4) * 100, 2)
    average_length = round(sum(len(record) for record in non_empty) / len(non_empty), 2) if non_empty else 0.0
    metrics = {
        "total_records": total,
        "non_empty_records": len(non_empty),
        "empty_records": total - len(non_empty),
        "duplicate_records": len(non_empty) - len(set(non_empty)),
        "completeness_percent": round(completeness * 100, 2),
        "uniqueness_percent": round(uniqueness * 100, 2),
        "average_length": average_length,
        "score": score,
        "threshold": threshold,
    }
    return {"status": "PASS" if score >= threshold else "REVIEW", "metrics": metrics}


class Handler(BaseHTTPRequestHandler):
    server_version = "qnet-quality"

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
        return bool(PUBLIC_TOKEN) and hmac.compare_digest(self.headers.get("X-API-Token", ""), PUBLIC_TOKEN)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health/live":
            self.send_json(200, {"status": "live", "service": "quality", "version": APP_VERSION})
        elif self.path == "/health/ready":
            ready = bool(PUBLIC_TOKEN) and 0 <= THRESHOLD <= 100
            self.send_json(200 if ready else 503, {"status": "ready" if ready else "not-ready", "threshold": THRESHOLD})
        elif self.path in ("/api/quality", "/api/quality/"):
            self.send_json(200, {"service": "quality", "version": APP_VERSION, "threshold": THRESHOLD, "endpoint": "POST /api/quality/evaluate"})
        else:
            self.send_json(404, {"error": "route not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/api/quality/evaluate":
            self.send_json(404, {"error": "route not found"})
            return
        if not self.authorized():
            self.send_json(401, {"error": "invalid or missing X-API-Token"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 2_097_152:
                raise ValueError("request body must be between 1 byte and 2 MiB")
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            records = payload.get("records")
            if not isinstance(records, list) or not all(isinstance(record, str) for record in records):
                raise ValueError("records must be an array of strings")
            result = evaluate(records)
            response = {"service": "quality", "version": APP_VERSION, "dataset": payload.get("dataset", "unnamed"), **result}
            print(json.dumps({"at": datetime.now(timezone.utc).isoformat(), "event": "quality_evaluated", "dataset": response["dataset"], **result["metrics"]}), flush=True)
            self.send_json(200, response)
        except (ValueError, json.JSONDecodeError) as exc:
            self.send_json(400, {"error": str(exc)})


if __name__ == "__main__":
    print(json.dumps({"event": "service_started", "service": "quality", "version": APP_VERSION, "threshold": THRESHOLD, "port": PORT}), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
