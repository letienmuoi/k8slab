@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "SA=pipeline-observer"
set "ROLE=pipeline-pod-reader"
set "BINDING=pipeline-observer-reads-pods"
set "POD=pipeline-rbac-observer"
set "RBAC_MANIFEST=lab-3.3-serviceaccount-rbac.yaml"
set "POD_MANIFEST=lab-3.3-observer-pod.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="apply" goto :apply_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :deploy
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 3.3 hoàn tất: ServiceAccount list Pods qua API và không có quyền đọc Secrets.
exit /b 0

:apply_action
call :precheck
if errorlevel 1 goto :fail
call :deploy
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
kubectl delete -f "%POD_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete -f "%RBAC_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa ServiceAccount, Role, RoleBinding và Pod của Lab 3.3.
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
kubectl apply --dry-run=server -f "%RBAC_MANIFEST%" >nul
if errorlevel 1 exit /b 1
kubectl apply --dry-run=client -f "%POD_MANIFEST%" >nul
exit /b %errorlevel%

:deploy
echo.
echo [Lab 3.3] Reset và apply ServiceAccount, Role, RoleBinding, Pod...
kubectl delete -f "%POD_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete -f "%RBAC_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%RBAC_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply --dry-run=server -f "%POD_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply -f "%POD_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready pod/%POD% --timeout=120s
exit /b %errorlevel%

:verify
kubectl get serviceaccount "%SA%" -n "%NS%" >nul 2>&1
if errorlevel 1 exit /b 1
kubectl get role "%ROLE%" -n "%NS%" >nul 2>&1
if errorlevel 1 exit /b 1
kubectl get rolebinding "%BINDING%" -n "%NS%" >nul 2>&1
if errorlevel 1 exit /b 1
kubectl get pod "%POD%" -n "%NS%" >nul 2>&1
if errorlevel 1 exit /b 1
set "CAN_LIST_PODS="
set "CAN_LIST_SECRETS="
set "ACTUAL_SA="
for /f "delims=" %%A in ('kubectl auth can-i list pods --as=system:serviceaccount:%NS%:%SA% -n "%NS%"') do set "CAN_LIST_PODS=%%A"
for /f "delims=" %%A in ('kubectl auth can-i list secrets --as=system:serviceaccount:%NS%:%SA% -n "%NS%"') do set "CAN_LIST_SECRETS=%%A"
for /f "delims=" %%A in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.serviceAccountName}"') do set "ACTUAL_SA=%%A"
echo can_list_pods=%CAN_LIST_PODS%
echo can_list_secrets=%CAN_LIST_SECRETS%
echo expected_service_account=%SA%
echo actual_service_account=%ACTUAL_SA%
if not "%CAN_LIST_PODS%"=="yes" exit /b 1
if not "%CAN_LIST_SECRETS%"=="no" exit /b 1
if not "%ACTUAL_SA%"=="%SA%" exit /b 1
kubectl exec "%POD%" -n "%NS%" -- /usr/bin/test -s /var/run/secrets/kubernetes.io/serviceaccount/token
if errorlevel 1 exit /b 1
kubectl logs "%POD%" -n "%NS%" --tail=10
if errorlevel 1 exit /b 1
kubectl logs "%POD%" -n "%NS%" --tail=10 | findstr /C:"event=rbac_api_list" >nul
if errorlevel 1 exit /b 1
kubectl logs "%POD%" -n "%NS%" --tail=10 | findstr /C:"http=200" >nul
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|apply^|verify^|cleanup^|help]
echo.
echo   run      Deploy RBAC resources and verify positive/negative permissions.
echo   apply    Server-dry-run and apply the manifest.
echo   verify   Check can-i, ServiceAccount token and in-Pod API logs.
echo   cleanup  Delete all Lab 3.3 resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 3.3 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl auth can-i --list --as=system:serviceaccount:%NS%:%SA% -n %NS%
echo Gợi ý: kubectl describe pod %POD% -n %NS%
exit /b 1
