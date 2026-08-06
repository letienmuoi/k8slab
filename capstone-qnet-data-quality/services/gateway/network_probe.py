"""Succeed only when NetworkPolicy blocks an unauthorized direct call."""

import os
import urllib.request


target = os.getenv("DENIED_URL", "http://qnet-normalizer:8080/health/ready")
try:
    with urllib.request.urlopen(target, timeout=4) as response:
        raise SystemExit(f"policy failure: unauthorized request returned HTTP {response.status}")
except OSError as exc:
    print(f'{{"event":"network_policy_verified","target":"{target}","blocked":true,"reason":"{exc}"}}')
