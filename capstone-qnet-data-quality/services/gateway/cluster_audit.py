"""CronJob entrypoint: list Capstone Pods using the mounted SA token."""

import json
import os
import ssl
import urllib.parse
import urllib.request
from pathlib import Path


token_path = Path("/var/run/secrets/kubernetes.io/serviceaccount/token")
ca_path = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
namespace = Path("/var/run/secrets/kubernetes.io/serviceaccount/namespace").read_text(encoding="utf-8").strip()
token = token_path.read_text(encoding="utf-8").strip()
host = os.environ["KUBERNETES_SERVICE_HOST"]
port = os.environ.get("KUBERNETES_SERVICE_PORT_HTTPS", "443")
selector = urllib.parse.quote("app.kubernetes.io/part-of=qnet-data-quality")
url = f"https://{host}:{port}/api/v1/namespaces/{namespace}/pods?labelSelector={selector}"
request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
context = ssl.create_default_context(cafile=ca_path)

with urllib.request.urlopen(request, context=context, timeout=10) as response:
    payload = json.load(response)

pods = []
ready_count = 0
for item in payload.get("items", []):
    statuses = item.get("status", {}).get("containerStatuses", [])
    ready = bool(statuses) and all(status.get("ready", False) for status in statuses)
    ready_count += int(ready)
    pods.append({
        "name": item["metadata"]["name"],
        "phase": item.get("status", {}).get("phase", "Unknown"),
        "ready": ready,
    })

print(json.dumps({
    "event": "kubernetes_api_audit",
    "namespace": namespace,
    "http": 200,
    "pod_count": len(pods),
    "ready_count": ready_count,
    "pods": pods,
}, ensure_ascii=False))
