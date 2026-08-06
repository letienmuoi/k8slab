"""Build the gateway runtime configuration in the init container."""

import json
import os
from pathlib import Path


def required(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"missing required environment variable: {name}")
    return value.rstrip("/")


def main() -> None:
    output = Path(os.getenv("RUNTIME_CONFIG", "/work/runtime.json"))
    config = {
        "domain": "QNET AI Data Quality Platform",
        "services": {
            "ingest": required("INGEST_URL"),
            "normalizer": required("NORMALIZER_URL"),
            "quality": required("QUALITY_URL"),
            "catalog": required("CATALOG_URL"),
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(config, indent=2), encoding="utf-8")
    print(json.dumps({"event": "runtime_config_created", "path": str(output)}))


if __name__ == "__main__":
    main()
