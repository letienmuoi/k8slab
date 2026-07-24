@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "POLICY=pipeline-backend-isolation"
set "MANIFEST=lab-4.3-networkpolicy.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="baseline" goto :baseline_action
if /I "%ACTION%"=="apply" goto :apply_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :require_kubectl
if errorlevel 1 goto :fail
call :ensure_app
if errorlevel 1 goto :fail
call :remove_policy
if errorlevel 1 goto :fail
call :baseline
if errorlevel 1 goto :fail
call :apply_policy
if errorlevel 1 goto :fail
call :verify_policy
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 4.3 hoàn tất: chỉ frontend vào backend; backend internet egress bị chặn.
exit /b 0

:baseline_action
call :require_kubectl
if errorlevel 1 goto :fail
call :ensure_app
if errorlevel 1 goto :fail
call :remove_policy
if errorlevel 1 goto :fail
call :baseline
if errorlevel 1 goto :fail
exit /b 0

:apply_action
call :require_kubectl
if errorlevel 1 goto :fail
call :ensure_app
if errorlevel 1 goto :fail
call :apply_policy
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_kubectl
if errorlevel 1 goto :fail
kubectl get networkpolicy "%POLICY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có networkpolicy/%POLICY%.
  goto :fail
)
call :verify_policy
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call :remove_policy
if errorlevel 1 goto :fail
echo [Lab 4.3] Xác nhận direct backend access đã được khôi phục...
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 5 http://pipeline-backend:8080/ready >nul
if errorlevel 1 goto :fail
echo [OK] Đã xóa NetworkPolicy và khôi phục traffic.
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

:ensure_app
kubectl get service pipeline-backend pipeline-frontend -n "%NS%" >nul 2>&1
if errorlevel 1 (
  call lab-4.1.bat run
  if errorlevel 1 exit /b 1
)
set "BACKEND_SELECTOR="
for /f "delims=" %%S in ('kubectl get service pipeline-backend -n "%NS%" -o jsonpath^="{.spec.selector.component}"') do set "BACKEND_SELECTOR=%%S"
if not "%BACKEND_SELECTOR%"=="normalizer-backend" (
  call lab-4.1.bat fix
  if errorlevel 1 exit /b 1
)
exit /b 0

:remove_policy
kubectl delete networkpolicy "%POLICY%" -n "%NS%" --ignore-not-found --wait=true
exit /b %errorlevel%

:baseline
echo.
echo [Lab 4.3] Baseline: frontend, non-frontend và internet đều reachable...
kubectl exec -n "%NS%" deployment/pipeline-frontend -c frontend -- /usr/bin/curl -fsS --max-time 5 http://pipeline-backend:8080/api?line=frontend-baseline >nul
if errorlevel 1 exit /b 1
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 5 http://pipeline-backend:8080/api?line=unauthorized-baseline >nul
if errorlevel 1 exit /b 1
kubectl exec -n "%NS%" deployment/pipeline-backend -c backend -- /usr/bin/curl -fsS --max-time 10 https://example.com >nul
if errorlevel 1 (
  echo [ERROR] Backend chưa ra internet được trước policy; negative egress test sẽ không có baseline.
  exit /b 1
)
echo baseline_frontend_to_backend=allowed
echo baseline_other_pod_to_backend=allowed
echo baseline_backend_to_internet=allowed
exit /b 0

:apply_policy
echo.
echo [Lab 4.3] Apply backend ingress/egress isolation...
kubectl apply --dry-run=server -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
ping -n 3 127.0.0.1 >nul
exit /b 0

:verify_policy
echo.
echo [Lab 4.3] Positive: frontend Pod vẫn gọi backend...
kubectl exec -n "%NS%" deployment/pipeline-frontend -c frontend -- /usr/bin/curl -fsS --max-time 5 http://pipeline-backend:8080/api?line=frontend-allowed
if errorlevel 1 exit /b 1
echo [Lab 4.3] Positive: client gọi frontend proxy, rồi frontend gọi backend...
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 5 http://pipeline-frontend:8080/api?line=proxy-allowed
if errorlevel 1 exit /b 1
echo [Lab 4.3] Negative: non-frontend gọi thẳng backend...
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 3 http://pipeline-backend:8080/api?line=must-be-denied >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Non-frontend Pod vẫn gọi được backend; CNI không enforce policy như mong đợi.
  exit /b 1
)
echo unauthorized_ingress=blocked_as_expected
echo [Lab 4.3] DNS backend vẫn được phép:
kubectl exec -n "%NS%" deployment/pipeline-backend -c backend -- /usr/bin/getent hosts example.com
if errorlevel 1 exit /b 1
echo [Lab 4.3] HTTPS internet từ backend phải bị chặn:
kubectl exec -n "%NS%" deployment/pipeline-backend -c backend -- /usr/bin/curl -fsS --max-time 3 https://example.com >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Backend vẫn ra internet được ngoài dự kiến.
  exit /b 1
)
echo backend_internet_egress=blocked_as_expected
kubectl describe networkpolicy "%POLICY%" -n "%NS%"
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|baseline^|apply^|verify^|cleanup^|help]
echo.
echo   run       Prove baseline, apply policy and run positive/negative tests.
echo   baseline  Remove policy and prove all baseline paths are reachable.
echo   apply     Apply backend ingress and egress isolation.
echo   verify    Require frontend allow, other-Pod deny and internet deny.
echo   cleanup   Delete policy and verify direct traffic is restored.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 4.3 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe networkpolicy %POLICY% -n %NS%
echo Gợi ý: kubectl get pods -n %NS% -l lab=4.1 --show-labels
exit /b 1
