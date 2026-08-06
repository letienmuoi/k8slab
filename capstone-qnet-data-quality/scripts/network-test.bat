@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

kubectl delete job qnet-network-deny-test -n qnet-capstone --ignore-not-found --wait=true || exit /b 1
kubectl apply -f .\k8s\tests\network-deny-job.yaml || exit /b 1
kubectl wait -n qnet-capstone --for=condition=complete job/qnet-network-deny-test --timeout=90s || (
  kubectl logs job/qnet-network-deny-test -n qnet-capstone
  exit /b 1
)
kubectl logs job/qnet-network-deny-test -n qnet-capstone
echo [OK] Unauthorized Pod bị chặn khi gọi thẳng normalizer.
