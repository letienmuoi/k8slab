@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

kubectl delete job qnet-smoke-test -n qnet-capstone --ignore-not-found --wait=true || exit /b 1
kubectl apply -f .\k8s\tests\smoke-job.yaml || exit /b 1
kubectl wait -n qnet-capstone --for=condition=complete job/qnet-smoke-test --timeout=180s || (
  kubectl describe job qnet-smoke-test -n qnet-capstone
  kubectl logs job/qnet-smoke-test -n qnet-capstone
  exit /b 1
)
kubectl logs job/qnet-smoke-test -n qnet-capstone
echo [OK] End-to-end smoke test đã đi qua gateway, ingest, normalizer, quality và catalog.
