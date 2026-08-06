#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."

target="${1:-all}"
action="${2:-}"

build_version() {
  version="$1"
  for service in gateway ingest normalizer quality catalog; do
    image="mualanhlung017/qnet-${service}:${version}"
    docker build --build-arg "APP_VERSION=${version}" -t "$image" "services/${service}"
    if [ "$action" = "push" ]; then docker push "$image"; fi
  done
}

if [ "$target" = "all" ]; then
  build_version 1.0.0
  build_version 1.1.0
else
  build_version "$target"
fi
