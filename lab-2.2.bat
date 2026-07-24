@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "MANIFEST=lab-2.2-blue-green.yaml"
set "BLUE=pipeline-release-blue"
set "GREEN=pipeline-release-green"
set "SERVICE=pipeline-release-gateway"
set "URL=http://pipeline-release-gateway:8080/"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="deploy" goto :deploy_action
if /I "%ACTION%"=="switch-green" goto :green_action
if /I "%ACTION%"=="switch-blue" goto :blue_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :deploy_both
if errorlevel 1 goto :fail
call :switch_color green
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 2.2 hoàn tất: blue và green cùng chạy, Service đã switch sang green.
echo Dùng "%~nx0 switch-blue" để rollback traffic hoặc "%~nx0 cleanup" để xóa lab.
exit /b 0

:deploy_action
call :precheck
if errorlevel 1 goto :fail
call :deploy_both
if errorlevel 1 goto :fail
exit /b 0

:green_action
call :require_resources
if errorlevel 1 goto :fail
call :switch_color green
if errorlevel 1 goto :fail
exit /b 0

:blue_action
call :require_resources
if errorlevel 1 goto :fail
call :switch_color blue
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_resources
if errorlevel 1 goto :fail
call :show_state
exit /b %errorlevel%

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete pods -n "%NS%" -l lab=2.2 --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa Service, ConfigMap, hai Deployment và Pods của Lab 2.2.
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 2.2] Kiểm tra dependency thật...
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-jobmanager --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-taskmanager --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/iceberg-rest --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/minio --timeout=30s
if errorlevel 1 exit /b 1
kubectl apply --dry-run=client -f "%MANIFEST%" >nul
exit /b %errorlevel%

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

:require_resources
call :require_kubectl
if errorlevel 1 exit /b 1
kubectl get deployment "%BLUE%" "%GREEN%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có đủ hai Deployment. Hãy chạy "%~nx0 deploy" trước.
  exit /b 1
)
kubectl get service "%SERVICE%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy service/%SERVICE%.
  exit /b 1
)
exit /b 0

:deploy_both
echo.
echo [Lab 2.2] Reset và deploy đồng thời blue + green...
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete pods -n "%NS%" -l lab=2.2 --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%BLUE% -n "%NS%" --timeout=180s
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%GREEN% -n "%NS%" --timeout=180s
if errorlevel 1 exit /b 1
call :wait_for_color blue
if errorlevel 1 exit /b 1
call :show_state
exit /b %errorlevel%

:switch_color
echo.
echo [Lab 2.2] Flip Service selector sang track=%~1...
kubectl patch service "%SERVICE%" -n "%NS%" --type=merge -p "{\"spec\":{\"selector\":{\"track\":\"%~1\"}}}"
if errorlevel 1 exit /b 1
call :wait_for_color %~1
if errorlevel 1 exit /b 1
call :assert_selector %~1
if errorlevel 1 exit /b 1
call :show_state
exit /b %errorlevel%

:wait_for_color
for /l %%T in (1,1,30) do (
  call :response_has_color %~1
  if not errorlevel 1 exit /b 0
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Service không route đến color=%~1 trong thời gian chờ.
exit /b 1

:response_has_color
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "%URL%" 2>nul | findstr /C:"color=%~1" >nul
exit /b %errorlevel%

:assert_selector
set "ACTUAL_TRACK="
for /f "delims=" %%S in ('kubectl get service "%SERVICE%" -n "%NS%" -o jsonpath^="{.spec.selector.track}"') do set "ACTUAL_TRACK=%%S"
echo expected_track=%~1
echo actual_track=%ACTUAL_TRACK%
if not "%ACTUAL_TRACK%"=="%~1" (
  echo [ERROR] Service selector không đúng kỳ vọng.
  exit /b 1
)
exit /b 0

:show_state
echo.
echo [Lab 2.2] Deployments:
kubectl get deployment "%BLUE%" "%GREEN%" -n "%NS%"
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.2] Pods:
kubectl get pods -n "%NS%" -l lab=2.2 -L track,release
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.2] Service selector:
kubectl get service "%SERVICE%" -n "%NS%" -o jsonpath="{.spec.selector}"
if errorlevel 1 exit /b 1
echo.
echo.
echo [Lab 2.2] EndpointSlices:
kubectl get endpointslice -n "%NS%" -l kubernetes.io/service-name=%SERVICE% -o wide
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.2] Response qua stable Service:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "%URL%"
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|deploy^|switch-green^|switch-blue^|verify^|cleanup^|help]
echo.
echo   run           Deploy blue and green, verify blue, then switch traffic to green.
echo   deploy        Reset and deploy both releases; Service starts on blue.
echo   switch-green  Flip the single Service selector to track=green.
echo   switch-blue   Flip the Service selector back to track=blue.
echo   verify        Show Deployments, Pods, selector, EndpointSlices and live response.
echo   cleanup       Delete only Lab 2.2 resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 2.2 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl get deployment,pod,service,endpointslice -n %NS% -l lab=2.2
echo Gợi ý: kubectl logs -n %NS% -l lab=2.2 --prefix=true --tail=50
exit /b 1
