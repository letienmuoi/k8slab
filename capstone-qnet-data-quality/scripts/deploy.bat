@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0.."

set "ENVIRONMENT=%~1"
if not defined ENVIRONMENT set "ENVIRONMENT=dev"
if /I not "%ENVIRONMENT%"=="dev" if /I not "%ENVIRONMENT%"=="prod" (
  echo Usage: %~nx0 [dev^|prod]
  exit /b 1
)

where kubectl >nul 2>&1 || (
  echo [ERROR] kubectl không có trong PATH.
  exit /b 1
)
kubectl cluster-info >nul 2>&1 || (
  echo [ERROR] Kubernetes cluster chưa sẵn sàng.
  exit /b 1
)

kubectl apply -f .\k8s\platform\namespace.yaml || exit /b 1
kubectl apply -k .\k8s\quota || exit /b 1
call .\scripts\create-secret.bat || exit /b 1

echo [VALIDATE] Kustomize overlay %ENVIRONMENT%
kubectl kustomize ".\k8s\overlays\%ENVIRONMENT%" | kubectl apply --dry-run=server -f - || exit /b 1
kubectl apply -k ".\k8s\overlays\%ENVIRONMENT%" || exit /b 1

for %%D in (qnet-gateway qnet-ingest qnet-normalizer-blue qnet-normalizer-green qnet-quality qnet-catalog) do (
  kubectl rollout status deployment/%%D -n qnet-capstone --timeout=240s || exit /b 1
)

kubectl get deployment,pod,service,hpa,pvc,cronjob -n qnet-capstone
echo [OK] QNET Capstone %ENVIRONMENT% đã sẵn sàng.
