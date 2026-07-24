@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "BASE=lab-2.4\base"
set "DEV=lab-2.4\overlays\dev"
set "PROD=lab-2.4\overlays\prod"
set "DEV_DEPLOY=pipeline-kustomize-auditor-dev"
set "PROD_DEPLOY=pipeline-kustomize-auditor-prod"
set "DEV_IMAGE=mualanhlung017/ai-data-pipeline:1.0.1"
set "PROD_IMAGE=mualanhlung017/ai-data-pipeline:1.0.2"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="render" goto :render_action
if /I "%ACTION%"=="dev" goto :dev_action
if /I "%ACTION%"=="prod" goto :prod_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
call :validate_overlays
if errorlevel 1 goto :fail
call :apply_dev
if errorlevel 1 goto :fail
call :apply_prod
if errorlevel 1 goto :fail
call :show_comparison
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 2.4 hoàn tất: một base đã tạo dev 1 replica/v1.0.1 và prod 3 replicas/v1.0.2.
echo Dùng "%~nx0 cleanup" để xóa hai Deployment của lab.
exit /b 0

:render_action
call :require_cli
if errorlevel 1 goto :fail
echo.
echo ===== DEV RENDER =====
kubectl kustomize "%DEV%"
if errorlevel 1 goto :fail
echo.
echo ===== PROD RENDER =====
kubectl kustomize "%PROD%"
if errorlevel 1 goto :fail
exit /b 0

:dev_action
call :precheck
if errorlevel 1 goto :fail
call :apply_dev
if errorlevel 1 goto :fail
exit /b 0

:prod_action
call :precheck
if errorlevel 1 goto :fail
call :apply_prod
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_kubectl
if errorlevel 1 goto :fail
kubectl get deployment "%DEV_DEPLOY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có deployment/%DEV_DEPLOY%.
  goto :fail
)
kubectl get deployment "%PROD_DEPLOY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có deployment/%PROD_DEPLOY%.
  goto :fail
)
call :verify_deployment "%DEV_DEPLOY%" "%DEV_IMAGE%" 1 dev
if errorlevel 1 goto :fail
call :verify_deployment "%PROD_DEPLOY%" "%PROD_IMAGE%" 3 prod
if errorlevel 1 goto :fail
call :show_comparison
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
echo [OK] Đã xóa toàn bộ resource có label lab=2.4.
exit /b 0

:require_cli
where kubectl >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy kubectl trong PATH.
  exit /b 1
)
exit /b 0

:require_kubectl
call :require_cli
if errorlevel 1 exit /b 1
kubectl get namespace "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Namespace %NS% chưa tồn tại.
  exit /b 1
)
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 2.4] Kiểm tra dependency thật của project...
for %%D in (flink-jobmanager flink-taskmanager iceberg-rest minio) do (
  kubectl wait -n "%NS%" --for=condition=Available deployment/%%D --timeout=30s
  if errorlevel 1 exit /b 1
)
exit /b 0

:reset_lab
echo [Lab 2.4] Dọn kết quả apply cũ nếu có...
kubectl delete -k "%DEV%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete -k "%PROD%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete deployment,pod -n "%NS%" -l lab=2.4 --ignore-not-found --wait=true
exit /b %errorlevel%

:validate_overlays
echo.
echo [Lab 2.4] Render và server-side dry-run overlay dev...
kubectl kustomize "%DEV%" | kubectl apply --dry-run=server -f -
if errorlevel 1 exit /b 1
echo [Lab 2.4] Render và server-side dry-run overlay prod...
kubectl kustomize "%PROD%" | kubectl apply --dry-run=server -f -
exit /b %errorlevel%

:apply_dev
echo.
echo [Lab 2.4] Apply dev overlay...
kubectl apply -k "%DEV%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEV_DEPLOY% -n "%NS%" --timeout=120s
if errorlevel 1 exit /b 1
call :verify_deployment "%DEV_DEPLOY%" "%DEV_IMAGE%" 1 dev
exit /b %errorlevel%

:apply_prod
echo.
echo [Lab 2.4] Apply prod overlay từ cùng base...
kubectl apply -k "%PROD%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%PROD_DEPLOY% -n "%NS%" --timeout=120s
if errorlevel 1 exit /b 1
call :verify_deployment "%PROD_DEPLOY%" "%PROD_IMAGE%" 3 prod
exit /b %errorlevel%

:verify_deployment
set "VERIFY_DEPLOY=%~1"
set "EXPECTED_IMAGE=%~2"
set "EXPECTED_REPLICAS=%~3"
set "EXPECTED_ENV=%~4"
set "ACTUAL_IMAGE="
set "ACTUAL_REPLICAS="
set "READY_REPLICAS="
for /f "delims=" %%I in ('kubectl get deployment "%VERIFY_DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[0].image}"') do set "ACTUAL_IMAGE=%%I"
for /f "delims=" %%R in ('kubectl get deployment "%VERIFY_DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.replicas}"') do set "ACTUAL_REPLICAS=%%R"
for /f "delims=" %%R in ('kubectl get deployment "%VERIFY_DEPLOY%" -n "%NS%" -o jsonpath^="{.status.readyReplicas}"') do set "READY_REPLICAS=%%R"
echo deployment=%VERIFY_DEPLOY%
echo expected_image=%EXPECTED_IMAGE%
echo actual_image=%ACTUAL_IMAGE%
echo expected_replicas=%EXPECTED_REPLICAS%
echo actual_replicas=%ACTUAL_REPLICAS%
echo ready_replicas=%READY_REPLICAS%
if not "%ACTUAL_IMAGE%"=="%EXPECTED_IMAGE%" exit /b 1
if not "%ACTUAL_REPLICAS%"=="%EXPECTED_REPLICAS%" exit /b 1
if not "%READY_REPLICAS%"=="%EXPECTED_REPLICAS%" exit /b 1
kubectl get pods -n "%NS%" -l "lab=2.4,environment=%EXPECTED_ENV%" -o wide
if errorlevel 1 exit /b 1
echo [Lab 2.4] Log audit nghiệp vụ của %EXPECTED_ENV%:
kubectl logs -n "%NS%" -l "lab=2.4,environment=%EXPECTED_ENV%" --prefix=true --tail=8 --max-log-requests=4
exit /b %errorlevel%

:show_comparison
echo.
echo [Lab 2.4] So sánh hai kết quả từ cùng một base:
kubectl get deployment -n "%NS%" -l lab=2.4 -L environment -o custom-columns="NAME:.metadata.name,ENV:.metadata.labels.environment,READY:.status.readyReplicas,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image"
if errorlevel 1 exit /b 1
echo.
kubectl get pods -n "%NS%" -l lab=2.4 -L environment
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|render^|dev^|prod^|verify^|cleanup^|help]
echo.
echo   run      Validate, apply and verify both overlays.
echo   render   Render dev and prod YAML without changing the cluster.
echo   dev      Apply and verify dev: image 1.0.1, one replica.
echo   prod     Apply and verify prod: image 1.0.2, three replicas.
echo   verify   Compare deployed image tags, replicas and Pods.
echo   cleanup  Delete all Lab 2.4 resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 2.4 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl kustomize .\%PROD%
echo Gợi ý: kubectl get deployment,pod -n %NS% -l lab=2.4
exit /b 1
