"""In-cluster end-to-end smoke test used by the smoke Job."""

import json
import os
import time
import urllib.request


gateway = os.getenv("GATEWAY_URL", "http://qnet-gateway:8080").rstrip("/")
token = os.environ["PUBLIC_API_TOKEN"]


def call(path: str, method: str = "GET", body=None):
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Accept": "application/json", "X-API-Token": token}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(gateway + path, data=data, method=method, headers=headers)
    with urllib.request.urlopen(request, timeout=15) as response:
        return response.status, json.load(response)


deadline = time.monotonic() + 60
while True:
    try:
        code, status = call("/api/status")
        if code == 200:
            break
    except OSError:
        pass
    if time.monotonic() >= deadline:
        raise RuntimeError("gateway dependencies did not become ready")
    time.sleep(2)

dataset = f"smoke-{int(time.time())}"
code, result = call("/api/ingest", "POST", {
    "dataset": dataset,
    "records": ["  QNET   CKAD  ", "ＡＩ DATA", "qnet ckad", ""],
})
assert code == 201, result
assert result["quality"]["metrics"]["total_records"] == 4, result
assert result["normalized_records"][0] == "qnet ckad", result

code, catalog = call("/api/catalog")
assert code == 200, catalog
assert any(item["dataset"] == dataset for item in catalog["items"]), catalog

print(json.dumps({"event": "smoke_test_passed", "dataset": dataset, "ingestion_id": result["ingestion_id"], "quality_score": result["quality"]["metrics"]["score"]}))
