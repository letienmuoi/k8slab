@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=pipeline-quota-lab"
set "PROJECT_NS=data-platform"
set "QUOTA=pipeline-compute-quota"
set "LIMIT_RANGE=pipeline-container-defaults"
set "ALLOWED_POD=quota-auditor-allowed"
set "OVERFLOW_POD=quota-auditor-overflow"
set "NS_MANIFEST=lab-3.4-namespace.yaml"
set "POLICY_MANIFEST=lab-3.4-quota-policy.yaml"
set "ALLOWED_MANIFEST=lab-3.4-allowed-pod.yaml"
set "OVERFLOW_MANIFEST=lab-3.4-overflow-pod.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="setup" goto :setup_action
if /I "%ACTION%"=="allowed" goto :allowed_action
if /I "%ACTION%"=="reject" goto :reject_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :reset_namespace
if errorlevel 1 goto :fail
call :setup
if errorlevel 1 goto :fail
call :create_allowed
if errorlevel 1 goto :fail
call :verify_allowed
if errorlevel 1 goto :fail
call :expect_rejection
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 3.4 hoàn tất: LimitRange defaulted Pod đầu và ResourceQuota từ chối Pod thứ hai.
exit /b 0

:setup_action
call :precheck
if errorlevel 1 goto :fail
call :reset_namespace
if errorlevel 1 goto :fail
call :setup
if errorlevel 1 goto :fail
exit /b 0

:allowed_action
call :require_policy
if errorlevel 1 goto :fail
call :create_allowed
if errorlevel 1 goto :fail
call :verify_allowed
if errorlevel 1 goto :fail
exit /b 0

:reject_action
call :require_allowed
if errorlevel 1 goto :fail
call :expect_rejection
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_allowed
if errorlevel 1 goto :fail
call :verify_allowed
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_cli
if errorlevel 1 goto :fail
call :reset_namespace
if errorlevel 1 goto :fail
echo [OK] Đã xóa namespace và toàn bộ resource của Lab 3.4.
exit /b 0

:require_cli
where kubectl >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy kubectl trong PATH.
  exit /b 1
)
exit /b 0

:precheck
call :require_cli
if errorlevel 1 exit /b 1
kubectl get namespace "%PROJECT_NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Namespace %PROJECT_NS% chưa tồn tại.
  exit /b 1
)
for %%D in (flink-jobmanager iceberg-rest minio) do (
  kubectl wait -n "%PROJECT_NS%" --for=condition=Available deployment/%%D --timeout=30s
  if errorlevel 1 exit /b 1
)
kubectl apply --dry-run=client -f "%NS_MANIFEST%" >nul
if errorlevel 1 exit /b 1
kubectl apply --dry-run=client -f "%POLICY_MANIFEST%" >nul
if errorlevel 1 exit /b 1
kubectl apply --dry-run=client -f "%ALLOWED_MANIFEST%" >nul
if errorlevel 1 exit /b 1
kubectl apply --dry-run=client -f "%OVERFLOW_MANIFEST%" >nul
exit /b %errorlevel%

:require_policy
call :require_cli
if errorlevel 1 exit /b 1
kubectl get resourcequota "%QUOTA%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có ResourceQuota. Chạy "%~nx0 setup" trước.
  exit /b 1
)
kubectl get limitrange "%LIMIT_RANGE%" -n "%NS%" >nul 2>&1
if errorlevel 1 exit /b 1
exit /b 0

:require_allowed
call :require_policy
if errorlevel 1 exit /b 1
kubectl get pod "%ALLOWED_POD%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có Pod được phép. Chạy "%~nx0 allowed" trước.
  exit /b 1
)
exit /b 0

:reset_namespace
kubectl delete namespace "%NS%" --ignore-not-found --wait=true --timeout=120s
exit /b %errorlevel%

:setup
echo.
echo [Lab 3.4] Tạo namespace riêng...
kubectl apply -f "%NS_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait --for=jsonpath="{.status.phase}"=Active namespace/%NS% --timeout=60s
if errorlevel 1 exit /b 1
echo [Lab 3.4] Server-dry-run rồi apply LimitRange và ResourceQuota...
kubectl apply --dry-run=server -f "%POLICY_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply -f "%POLICY_MANIFEST%"
exit /b %errorlevel%

:create_allowed
echo.
echo [Lab 3.4] Tạo Pod đầu tiên không khai báo resources...
kubectl delete pod "%ALLOWED_POD%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%ALLOWED_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready pod/%ALLOWED_POD% --timeout=120s
exit /b %errorlevel%

:verify_allowed
set "REQUEST_CPU="
set "REQUEST_MEMORY="
set "LIMIT_CPU="
set "LIMIT_MEMORY="
for /f "delims=" %%V in ('kubectl get pod "%ALLOWED_POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].resources.requests.cpu}"') do set "REQUEST_CPU=%%V"
for /f "delims=" %%V in ('kubectl get pod "%ALLOWED_POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].resources.requests.memory}"') do set "REQUEST_MEMORY=%%V"
for /f "delims=" %%V in ('kubectl get pod "%ALLOWED_POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].resources.limits.cpu}"') do set "LIMIT_CPU=%%V"
for /f "delims=" %%V in ('kubectl get pod "%ALLOWED_POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].resources.limits.memory}"') do set "LIMIT_MEMORY=%%V"
echo request_cpu=%REQUEST_CPU%
echo request_memory=%REQUEST_MEMORY%
echo limit_cpu=%LIMIT_CPU%
echo limit_memory=%LIMIT_MEMORY%
if not "%REQUEST_CPU%"=="100m" exit /b 1
if not "%REQUEST_MEMORY%"=="64Mi" exit /b 1
if not "%LIMIT_CPU%"=="200m" exit /b 1
if not "%LIMIT_MEMORY%"=="128Mi" exit /b 1
kubectl get resourcequota "%QUOTA%" -n "%NS%"
if errorlevel 1 exit /b 1
kubectl logs "%ALLOWED_POD%" -n "%NS%" --tail=10
if errorlevel 1 exit /b 1
kubectl logs "%ALLOWED_POD%" -n "%NS%" --tail=10 | findstr /C:"event=quota_dependency_audit" >nul
exit /b %errorlevel%

:expect_rejection
echo.
echo [Lab 3.4] Tạo Pod thứ hai và chờ API server từ chối vì CPU quota...
kubectl delete pod "%OVERFLOW_POD%" -n "%NS%" --ignore-not-found --wait=true >nul 2>&1
set "REJECTION_LOG=%TEMP%\lab-3.4-quota-rejection-%RANDOM%.log"
kubectl apply -f "%OVERFLOW_MANIFEST%" >"%REJECTION_LOG%" 2>&1
if errorlevel 1 goto :rejection_received
echo [ERROR] Pod overflow được tạo ngoài dự kiến.
type "%REJECTION_LOG%"
del /q "%REJECTION_LOG%" >nul 2>&1
kubectl delete pod "%OVERFLOW_POD%" -n "%NS%" --ignore-not-found --wait=true
exit /b 1

:rejection_received
type "%REJECTION_LOG%"
findstr /C:"exceeded quota" "%REJECTION_LOG%" >nul
if errorlevel 1 (
  echo [ERROR] Lệnh thất bại nhưng không phải do exceeded quota.
  del /q "%REJECTION_LOG%" >nul 2>&1
  exit /b 1
)
del /q "%REJECTION_LOG%" >nul 2>&1
kubectl get pod "%OVERFLOW_POD%" -n "%NS%" >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Pod overflow tồn tại dù admission phải từ chối.
  exit /b 1
)
echo rejection=expected_exceeded_quota
kubectl describe resourcequota "%QUOTA%" -n "%NS%"
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|setup^|allowed^|reject^|verify^|cleanup^|help]
echo.
echo   run      Create namespace/policies, admit one Pod and reject the second.
echo   setup    Recreate namespace, LimitRange and ResourceQuota.
echo   allowed  Create and verify the defaulted business-auditor Pod.
echo   reject   Attempt the second Pod and require an exceeded-quota error.
echo   verify   Show injected resources, quota usage and business logs.
echo   cleanup  Delete the isolated lab namespace.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 3.4 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe quota %QUOTA% -n %NS%
echo Gợi ý: kubectl get pod -n %NS% -o yaml
exit /b 1
