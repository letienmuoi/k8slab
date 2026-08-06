@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0.."

set "NS=qnet-capstone"
if not defined CAPSTONE_API_TOKEN (
  echo [ERROR] Hãy set CAPSTONE_API_TOKEN trước khi deploy.
  exit /b 1
)
if not defined CAPSTONE_CATALOG_TOKEN (
  echo [ERROR] Hãy set CAPSTONE_CATALOG_TOKEN trước khi deploy.
  exit /b 1
)

kubectl get namespace "%NS%" >nul 2>&1 || (
  echo [ERROR] Namespace %NS% chưa tồn tại.
  exit /b 1
)

kubectl create secret generic qnet-secrets -n "%NS%" ^
  --from-literal=public-api-token="%CAPSTONE_API_TOKEN%" ^
  --from-literal=catalog-api-token="%CAPSTONE_CATALOG_TOKEN%" ^
  --dry-run=client -o yaml | kubectl apply -f -
if errorlevel 1 exit /b 1
kubectl label secret qnet-secrets -n "%NS%" app.kubernetes.io/part-of=qnet-data-quality --overwrite
echo [OK] Secret đã được tạo từ environment, không lưu plaintext trong Git.
