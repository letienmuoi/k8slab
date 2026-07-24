@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "BACKEND_DEPLOY=pipeline-backend"
set "FRONTEND_DEPLOY=pipeline-frontend"
set "BACKEND_SERVICE=pipeline-backend"
set "FRONTEND_SERVICE=pipeline-frontend"
set "MANIFEST=lab-4.1-services.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="deploy" goto :deploy_action
if /I "%ACTION%"=="diagnose" goto :diagnose_action
if /I "%ACTION%"=="fix" goto :fix_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
call :deploy
if errorlevel 1 goto :fail
call :diagnose
if errorlevel 1 goto :fail
call :fix_selector
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 4.1 hoàn tất: ClusterIP, NodePort, selector fix và Endpoints đều đã kiểm chứng.
exit /b 0

:deploy_action
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
call :deploy
if errorlevel 1 goto :fail
exit /b 0

:diagnose_action
call :require_workload
if errorlevel 1 goto :fail
call :diagnose
if errorlevel 1 goto :fail
exit /b 0

:fix_action
call :require_workload
if errorlevel 1 goto :fail
call :fix_selector
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_workload
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
echo [OK] Đã xóa frontend, backend và Services của Lab 4.1.
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

:require_workload
call :require_kubectl
if errorlevel 1 exit /b 1
kubectl get deployment "%BACKEND_DEPLOY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có Lab 4.1 workload. Chạy "%~nx0 deploy" trước.
  exit /b 1
)
kubectl get deployment "%FRONTEND_DEPLOY%" -n "%NS%" >nul 2>&1
exit /b %errorlevel%

:reset_lab
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete pod -n "%NS%" -l lab=4.1 --ignore-not-found --wait=true
exit /b %errorlevel%

:deploy
echo.
echo [Lab 4.1] Apply frontend/backend với backend selector cố ý sai...
kubectl apply --dry-run=server -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%BACKEND_DEPLOY% -n "%NS%" --timeout=120s
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%FRONTEND_DEPLOY% -n "%NS%" --timeout=120s
exit /b %errorlevel%

:diagnose
echo.
echo [Lab 4.1] Diagnose selector mismatch...
set "BACKEND_SELECTOR="
for /f "delims=" %%S in ('kubectl get service "%BACKEND_SERVICE%" -n "%NS%" -o jsonpath^="{.spec.selector.component}"') do set "BACKEND_SELECTOR=%%S"
echo backend_service_selector=%BACKEND_SELECTOR%
if not "%BACKEND_SELECTOR%"=="normalizer-backend-broken" (
  echo [ERROR] Selector không ở trạng thái lỗi mong đợi.
  exit /b 1
)
set "ENDPOINT_COUNT=0"
for /f "delims=" %%E in ('kubectl get endpointslice -n "%NS%" -l kubernetes.io/service-name^=%BACKEND_SERVICE% -o jsonpath^="{range .items[*].endpoints[*]}{.addresses[0]}{'\n'}{end}"') do set /a ENDPOINT_COUNT+=1
echo backend_endpoints_before_fix=%ENDPOINT_COUNT%
if not "%ENDPOINT_COUNT%"=="0" exit /b 1
kubectl get endpoints "%BACKEND_SERVICE%" -n "%NS%"
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 5 "http://%FRONTEND_SERVICE%:8080/api?line=selector-check" >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Frontend gọi backend thành công dù selector đang sai.
  exit /b 1
)
echo frontend_to_backend_before_fix=failed_as_expected
exit /b 0

:fix_selector
echo.
echo [Lab 4.1] Patch Service selector về label thật của backend Pods...
kubectl patch service "%BACKEND_SERVICE%" -n "%NS%" --type=merge -p "{\"spec\":{\"selector\":{\"app\":\"ai-data-pipeline\",\"lab\":\"4.1\",\"component\":\"normalizer-backend\"}}}"
if errorlevel 1 exit /b 1
for /l %%T in (1,1,30) do (
  kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 3 "http://%BACKEND_SERVICE%:8080/ready" >nul 2>&1
  if not errorlevel 1 (
    echo backend_service_after_fix=ready
    exit /b 0
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Backend Service chưa có endpoint usable sau khi patch.
exit /b 1

:verify
echo.
echo [Lab 4.1] Verify Service types và Endpoints...
set "BACKEND_TYPE="
set "FRONTEND_TYPE="
set "ENDPOINT_COUNT=0"
for /f "delims=" %%T in ('kubectl get service "%BACKEND_SERVICE%" -n "%NS%" -o jsonpath^="{.spec.type}"') do set "BACKEND_TYPE=%%T"
for /f "delims=" %%T in ('kubectl get service "%FRONTEND_SERVICE%" -n "%NS%" -o jsonpath^="{.spec.type}"') do set "FRONTEND_TYPE=%%T"
for /f "delims=" %%E in ('kubectl get endpointslice -n "%NS%" -l kubernetes.io/service-name^=%BACKEND_SERVICE% -o jsonpath^="{range .items[*].endpoints[*]}{.addresses[0]}{'\n'}{end}"') do set /a ENDPOINT_COUNT+=1
echo backend_type=%BACKEND_TYPE%
echo frontend_type=%FRONTEND_TYPE%
echo backend_endpoints_after_fix=%ENDPOINT_COUNT%
if not "%BACKEND_TYPE%"=="ClusterIP" exit /b 1
if not "%FRONTEND_TYPE%"=="NodePort" exit /b 1
if not "%ENDPOINT_COUNT%"=="2" exit /b 1
kubectl get endpoints "%BACKEND_SERVICE%" "%FRONTEND_SERVICE%" -n "%NS%"
echo.
echo [Lab 4.1] ClusterIP response:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%BACKEND_SERVICE%:8080/api?line=%%20%%20DU%%20%%20%%20LIEU%%09AI%%20%%20"
if errorlevel 1 exit /b 1
set "NODE_IP="
set "NODE_PORT="
for /f "tokens=1,2 delims==" %%A in ('kubectl get nodes -o jsonpath^="{range .items[0].status.addresses[*]}{.type}={.address}{'\n'}{end}"') do if "%%A"=="InternalIP" set "NODE_IP=%%B"
for /f "delims=" %%P in ('kubectl get service "%FRONTEND_SERVICE%" -n "%NS%" -o jsonpath^="{.spec.ports[0].nodePort}"') do set "NODE_PORT=%%P"
echo.
echo node_ip=%NODE_IP%
echo node_port=%NODE_PORT%
if not "%NODE_PORT%"=="30081" exit /b 1
echo [Lab 4.1] NodePort frontend response:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%NODE_PORT%/"
if errorlevel 1 exit /b 1
echo [Lab 4.1] NodePort frontend to backend response:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%NODE_PORT%/api?line=KUBERNETES%%20DATA"
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|deploy^|diagnose^|fix^|verify^|cleanup^|help]
echo.
echo   run       Deploy broken selector, diagnose, fix and verify both Services.
echo   deploy    Reset and deploy the intentionally broken Service selector.
echo   diagnose  Require zero backend endpoints and failed frontend proxy.
echo   fix       Patch backend Service selector to match Pods.
echo   verify    Verify ClusterIP, NodePort and real normalization responses.
echo   cleanup   Delete all Lab 4.1 resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 4.1 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl get service,endpoints,endpointslice -n %NS% -l lab=4.1
echo Gợi ý: kubectl get pods -n %NS% -l lab=4.1 --show-labels
exit /b 1
