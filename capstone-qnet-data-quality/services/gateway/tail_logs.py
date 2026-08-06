"""Minimal sidecar that follows the gateway access log without shell tools."""

import os
import time
from pathlib import Path


path = Path(os.getenv("ACCESS_LOG_PATH", "/var/log/gateway/access.log"))
position = 0
print(f'{{"event":"sidecar_started","path":"{path}"}}', flush=True)

while True:
    try:
        if path.exists():
            with path.open("r", encoding="utf-8") as handle:
                handle.seek(position)
                for line in handle:
                    print(line.rstrip(), flush=True)
                position = handle.tell()
    except OSError as exc:
        print(f'{{"event":"sidecar_read_error","error":"{exc}"}}', flush=True)
    time.sleep(1)
