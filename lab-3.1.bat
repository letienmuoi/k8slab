@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "POD=pipeline-config-auditor"
set "SECRET=pipeline-catalog-secret"
set "CONFIG=pipeline-endpoints"
set "SECRET_FILE=lab-3.1-files\catalog-client.token.example"
set "MANIFEST=lab-3.1-config-secret-pod.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="create-config" goto :create_action
if /I "%ACTION%"=="pod" goto :pod_action
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
call :create_config
if errorlevel 1 goto :fail
call :deploy_pod
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 3.1 hoàn tất: Secret env và ConfigMap volume đã chạy với dependency thật.
exit /b 0

:create_action
call :precheck
if errorlevel 1 goto :fail
kubectl delete pod "%POD%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete secret "%SECRET%" -n "%NS%" --ignore-not-found
if errorlevel 1 goto :fail
kubectl delete configmap "%CONFIG%" -n "%NS%" --ignore-not-found
if errorlevel 1 goto :fail
call :create_config
if errorlevel 1 goto :fail
exit /b 0

:pod_action
call :require_kubectl
if errorlevel 1 goto :fail
kubectl get secret "%SECRET%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có secret/%SECRET%. Chạy "%~nx0 create-config" trước.
  goto :fail
)
kubectl get configmap "%CONFIG%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có configmap/%CONFIG%. Chạy "%~nx0 create-config" trước.
  goto :fail
)
call :deploy_pod
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_kubectl
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
echo [OK] Đã xóa Pod, ConfigMap và Secret của Lab 3.1.
exit /b 0

:require_kubectl
where kubectl >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy kubectl trong PATH.
  exit /b 1
)
kubectl get namespace "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Namespace %NS% chưa tồn tại.
  exit /b 1
)
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
if not exist "%SECRET_FILE%" (
  echo [ERROR] Không tìm thấy file %SECRET_FILE%.
  exit /b 1
)
for %%D in (flink-jobmanager iceberg-rest minio) do (
  kubectl wait -n "%NS%" --for=condition=Available deployment/%%D --timeout=30s
  if errorlevel 1 exit /b 1
)
exit /b 0

:reset_lab
kubectl delete pod "%POD%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete configmap "%CONFIG%" -n "%NS%" --ignore-not-found
if errorlevel 1 exit /b 1
kubectl delete secret "%SECRET%" -n "%NS%" --ignore-not-found
exit /b %errorlevel%

:create_config
echo.
echo [Lab 3.1] Tạo Secret từ file...
kubectl create secret generic "%SECRET%" -n "%NS%" --from-file=catalog-client.token="%SECRET_FILE%"
if errorlevel 1 exit /b 1
kubectl label secret "%SECRET%" -n "%NS%" app=ai-data-pipeline lab=3.1 component=config-auditor
if errorlevel 1 exit /b 1
echo [Lab 3.1] Tạo ConfigMap từ ba literal...
kubectl create configmap "%CONFIG%" -n "%NS%" --from-literal=flink.jobs.url=http://flink-jobmanager:8081/jobs/overview --from-literal=iceberg.tables.url=http://iceberg-rest:8181/v1/namespaces/medallion/tables --from-literal=minio.ready.url=http://minio:9000/minio/health/ready
if errorlevel 1 exit /b 1
kubectl label configmap "%CONFIG%" -n "%NS%" app=ai-data-pipeline lab=3.1 component=config-auditor
exit /b %errorlevel%

:deploy_pod
echo.
echo [Lab 3.1] Apply Pod dùng Secret env và ConfigMap volume...
kubectl delete pod "%POD%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready pod/%POD% --timeout=120s
exit /b %errorlevel%

:verify
kubectl get pod "%POD%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có pod/%POD%.
  exit /b 1
)
set "ACTUAL_SECRET="
set "ACTUAL_CONFIG="
for /f "delims=" %%S in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].env[0].valueFrom.secretKeyRef.name}"') do set "ACTUAL_SECRET=%%S"
for /f "delims=" %%C in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.volumes[0].configMap.name}"') do set "ACTUAL_CONFIG=%%C"
echo expected_secret=%SECRET%
echo actual_secret=%ACTUAL_SECRET%
echo expected_configmap=%CONFIG%
echo actual_configmap=%ACTUAL_CONFIG%
if not "%ACTUAL_SECRET%"=="%SECRET%" exit /b 1
if not "%ACTUAL_CONFIG%"=="%CONFIG%" exit /b 1
kubectl exec "%POD%" -n "%NS%" -- /usr/bin/printenv CATALOG_CLIENT_TOKEN >nul
if errorlevel 1 exit /b 1
echo [Lab 3.1] ConfigMap files:
kubectl exec "%POD%" -n "%NS%" -- /usr/bin/ls -l /etc/pipeline/endpoints
if errorlevel 1 exit /b 1
echo [Lab 3.1] Log nghiệp vụ:
kubectl logs "%POD%" -n "%NS%" --tail=10
if errorlevel 1 exit /b 1
kubectl logs "%POD%" -n "%NS%" --tail=10 | findstr /C:"event=config_audit" >nul
if errorlevel 1 exit /b 1
kubectl logs "%POD%" -n "%NS%" --tail=10 | findstr /C:"minio_http=200" >nul
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|create-config^|pod^|verify^|cleanup^|help]
echo.
echo   run            Create Secret/ConfigMap, deploy Pod and verify real audit.
echo   create-config  Create Secret from file and ConfigMap from literals.
echo   pod            Deploy the Pod after configuration exists.
echo   verify         Verify injection, mounted files and business logs.
echo   cleanup        Delete all Lab 3.1 resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 3.1 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe pod %POD% -n %NS%
echo Gợi ý: kubectl get secret,configmap -n %NS% -l lab=3.1
exit /b 1
