"""Bounded Job that inserts a real sample dataset through the gateway."""

import json
import os
import time
import urllib.request


gateway = os.getenv("GATEWAY_URL", "http://qnet-gateway:8080").rstrip("/")
token = os.environ["PUBLIC_API_TOKEN"]
dataset = os.getenv("SEED_DATASET", f"qnet-training-{int(time.time())}")
payload = {
    "dataset": dataset,
    "records": [
        "  Customer   ID 001  ",
        "ＣＵＳＴＯＭＥＲ ID 002",
        "customer id 001",
        " AI-ready   dataset ",
        "",
    ],
}
request = urllib.request.Request(
    gateway + "/api/ingest",
    data=json.dumps(payload).encode("utf-8"),
    method="POST",
    headers={"Content-Type": "application/json", "X-API-Token": token},
)
with urllib.request.urlopen(request, timeout=30) as response:
    result = json.load(response)
    if response.status != 201:
        raise RuntimeError(f"unexpected HTTP {response.status}: {result}")
print(json.dumps({"event": "seed_completed", "dataset": dataset, "result": result}, ensure_ascii=False))
