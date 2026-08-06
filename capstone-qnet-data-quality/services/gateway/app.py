"""North-south gateway for the QNET AI Data Quality Platform."""

from __future__ import annotations

import hmac
import json
import os
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


APP_VERSION = os.getenv("APP_VERSION", "dev")
PORT = int(os.getenv("PORT", "8080"))
CONFIG_PATH = Path(os.getenv("RUNTIME_CONFIG", "/work/runtime.json"))
ACCESS_LOG = Path(os.getenv("ACCESS_LOG_PATH", "/var/log/gateway/access.log"))
PUBLIC_TOKEN = os.getenv("PUBLIC_API_TOKEN", "")
CATALOG_TOKEN = os.getenv("CATALOG_API_TOKEN", "")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_config() -> dict[str, Any]:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def emit(event: dict[str, Any]) -> None:
    payload = json.dumps({"at": utc_now(), **event}, ensure_ascii=False)
    print(payload, flush=True)
    try:
        ACCESS_LOG.parent.mkdir(parents=True, exist_ok=True)
        with ACCESS_LOG.open("a", encoding="utf-8") as handle:
            handle.write(payload + "\n")
    except OSError as exc:
        print(json.dumps({"event": "access_log_write_failed", "error": str(exc)}), flush=True)


def request_json(url: str, method: str = "GET", body: Any = None, headers: dict[str, str] | None = None) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    request_headers = {"Accept": "application/json"}
    if data is not None:
        request_headers["Content-Type"] = "application/json"
    if headers:
        request_headers.update(headers)
    request = urllib.request.Request(url, data=data, method=method, headers=request_headers)
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            raw = response.read().decode("utf-8")
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"error": raw or str(exc)}
        return exc.code, payload


class Handler(BaseHTTPRequestHandler):
    server_version = "qnet-gateway"

    def log_message(self, _format: str, *_args: Any) -> None:
        return

    def send_json(self, status: int, payload: Any) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def read_json(self) -> Any:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 1_048_576:
            raise ValueError("request body must be between 1 byte and 1 MiB")
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def authorized(self) -> bool:
        supplied = self.headers.get("X-API-Token", "")
        return bool(PUBLIC_TOKEN) and hmac.compare_digest(supplied, PUBLIC_TOKEN)

    def do_GET(self) -> None:  # noqa: N802
        started = time.monotonic()
        status = 200
        try:
            if self.path == "/health/live":
                self.send_json(200, {"status": "live", "service": "gateway", "version": APP_VERSION})
                return
            if self.path == "/health/ready":
                ready = CONFIG_PATH.is_file() and bool(PUBLIC_TOKEN) and bool(CATALOG_TOKEN)
                self.send_json(200 if ready else 503, {"status": "ready" if ready else "not-ready"})
                return
            if self.path == "/" or self.path == "/api":
                config = load_config()
                self.send_json(200, {
                    "application": config["domain"],
                    "service": "gateway",
                    "version": APP_VERSION,
                    "endpoints": ["POST /api/ingest", "POST /api/normalize", "POST /api/quality/evaluate", "GET /api/catalog", "GET /api/status"],
                })
                return
            if not self.authorized():
                status = 401
                self.send_json(status, {"error": "invalid or missing X-API-Token"})
                return
            config = load_config()["services"]
            if self.path == "/api/catalog":
                status, payload = request_json(config["catalog"] + "/datasets", headers={"X-Catalog-Token": CATALOG_TOKEN})
                self.send_json(status, payload)
                return
            if self.path == "/api/status":
                checks: dict[str, Any] = {}
                for name, base_url in config.items():
                    try:
                        code, payload = request_json(base_url + "/health/ready")
                        checks[name] = {"http": code, "body": payload}
                    except OSError as exc:
                        checks[name] = {"http": 503, "error": str(exc)}
                status = 200 if all(item["http"] == 200 for item in checks.values()) else 503
                self.send_json(status, {"status": "ready" if status == 200 else "degraded", "dependencies": checks})
                return
            status = 404
            self.send_json(status, {"error": "route not found"})
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            status = 503
            self.send_json(status, {"error": str(exc)})
        finally:
            emit({"event": "http_request", "method": "GET", "path": self.path, "status": status, "duration_ms": round((time.monotonic() - started) * 1000, 2)})

    def do_POST(self) -> None:  # noqa: N802
        started = time.monotonic()
        status = 200
        try:
            if not self.authorized():
                status = 401
                self.send_json(status, {"error": "invalid or missing X-API-Token"})
                return
            body = self.read_json()
            services = load_config()["services"]
            routes = {
                "/api/ingest": (services["ingest"] + "/ingest", {}),
                "/api/normalize": (services["normalizer"] + "/normalize", {}),
                "/api/quality": (services["quality"] + "/api/quality/evaluate", {"X-API-Token": PUBLIC_TOKEN}),
                "/api/quality/evaluate": (services["quality"] + "/api/quality/evaluate", {"X-API-Token": PUBLIC_TOKEN}),
            }
            if self.path not in routes:
                status = 404
                self.send_json(status, {"error": "route not found"})
                return
            target, headers = routes[self.path]
            status, payload = request_json(target, method="POST", body=body, headers=headers)
            self.send_json(status, payload)
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            status = 502
            self.send_json(status, {"error": str(exc)})
        finally:
            emit({"event": "http_request", "method": "POST", "path": self.path, "status": status, "duration_ms": round((time.monotonic() - started) * 1000, 2)})


def main() -> None:
    emit({"event": "service_started", "service": "gateway", "version": APP_VERSION, "port": PORT})
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
