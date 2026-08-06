#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."

kubectl delete job qnet-smoke-test -n qnet-capstone --ignore-not-found --wait=true
kubectl apply -f k8s/tests/smoke-job.yaml
kubectl wait -n qnet-capstone --for=condition=complete job/qnet-smoke-test --timeout=180s
kubectl logs job/qnet-smoke-test -n qnet-capstone
