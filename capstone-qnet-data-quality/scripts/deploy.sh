#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."

environment="${1:-dev}"
case "$environment" in dev|prod) ;; *) echo "usage: $0 [dev|prod]" >&2; exit 1;; esac
: "${CAPSTONE_API_TOKEN:?set CAPSTONE_API_TOKEN}"
: "${CAPSTONE_CATALOG_TOKEN:?set CAPSTONE_CATALOG_TOKEN}"

kubectl apply -f k8s/platform/namespace.yaml
kubectl apply -k k8s/quota
kubectl create secret generic qnet-secrets -n qnet-capstone \
  --from-literal="public-api-token=${CAPSTONE_API_TOKEN}" \
  --from-literal="catalog-api-token=${CAPSTONE_CATALOG_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret qnet-secrets -n qnet-capstone app.kubernetes.io/part-of=qnet-data-quality --overwrite
kubectl kustomize "k8s/overlays/${environment}" | kubectl apply --dry-run=server -f -
kubectl apply -k "k8s/overlays/${environment}"

for deployment in qnet-gateway qnet-ingest qnet-normalizer-blue qnet-normalizer-green qnet-quality qnet-catalog; do
  kubectl rollout status "deployment/${deployment}" -n qnet-capstone --timeout=240s
done
