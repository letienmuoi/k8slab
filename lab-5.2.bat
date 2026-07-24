@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "METRICS_MANIFEST=lab-5.2-metrics-server.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="prepare" goto :prepare_action
if /I "%ACTION%"=="restart" goto :restart_action
if /I "%ACTION%"=="logs" goto :logs_action
if /I "%ACTION%"=="events" goto :events_action
if /I "%ACTION%"=="top" goto :top_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="cleanup-metrics" goto :cleanup_metrics
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :require_kubectl
if errorlevel 1 goto :fail
call :prepare
if errorlevel 1 goto :fail
call lab-5.1.bat break
if errorlevel 1 goto :fail
call :resolve_pod
if errorlevel 1 goto :fail
call :show_logs
if errorlevel 1 goto :fail
call :show_events
if errorlevel 1 goto :fail
call :show_top
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 5.2 hoàn tất: logs, previous logs, Events và Metrics API đều đã kiểm chứng.
exit /b 0

:prepare_action
call :require_kubectl
if errorlevel 1 goto :fail
call :prepare
if errorlevel 1 goto :fail
exit /b 0

:restart_action
call :require_workload
if errorlevel 1 goto :fail
call lab-5.1.bat break
if errorlevel 1 goto :fail
exit /b 0

:logs_action
call :require_workload
if errorlevel 1 goto :fail
call :resolve_pod
if errorlevel 1 goto :fail
call :show_logs
if errorlevel 1 goto :fail
exit /b 0

:events_action
call :require_workload
if errorlevel 1 goto :fail
call :resolve_pod
if errorlevel 1 goto :fail
call :show_events
if errorlevel 1 goto :fail
exit /b 0

:top_action
call :require_workload
if errorlevel 1 goto :fail
call :ensure_metrics
if errorlevel 1 goto :fail
call :resolve_pod
if errorlevel 1 goto :fail
call :show_top
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_workload
if errorlevel 1 goto :fail
call :ensure_metrics
if errorlevel 1 goto :fail
call :resolve_pod
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call lab-5.1.bat cleanup
if errorlevel 1 goto :fail
echo [OK] Đã xóa observability workload; Metrics Server được giữ lại.
exit /b 0

:cleanup_metrics
call :require_kubectl
if errorlevel 1 goto :fail
kubectl get deployment metrics-server -n kube-system >nul 2>&1
if errorlevel 1 (
  echo [Lab 5.2] Metrics Server không tồn tại; không cần cleanup.
  exit /b 0
)
set "METRICS_OWNER="
for /f "delims=" %%O in ('kubectl get deployment metrics-server -n kube-system -o jsonpath^="{.metadata.annotations.lab\.muoilt\.vn/managed-by}"') do set "METRICS_OWNER=%%O"
if not "!METRICS_OWNER!"=="lab-5.2" (
  echo [ERROR] Metrics Server không thuộc Lab 5.2; từ chối xóa.
  exit /b 1
)
kubectl delete -f "%METRICS_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã gỡ Metrics Server do Lab 5.2 cài.
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
kubectl get deployment pipeline-self-healing -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có workload Lab 5.1. Chạy "%~nx0 prepare" trước.
  exit /b 1
)
exit /b 0

:prepare
echo.
echo [Lab 5.2] Deploy lại workload để có baseline quan sát sạch...
call lab-5.1.bat deploy
if errorlevel 1 exit /b 1
call :ensure_metrics
exit /b %errorlevel%

:ensure_metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes >nul 2>&1
if not errorlevel 1 (
  echo [Lab 5.2] Metrics API đã hoạt động.
  exit /b 0
)
kubectl get deployment metrics-server -n kube-system >nul 2>&1
if not errorlevel 1 (
  set "EXISTING_OWNER="
  for /f "delims=" %%O in ('kubectl get deployment metrics-server -n kube-system -o jsonpath^="{.metadata.annotations.lab\.muoilt\.vn/managed-by}"') do set "EXISTING_OWNER=%%O"
  if not "!EXISTING_OWNER!"=="lab-5.2" (
    echo [ERROR] Có metrics-server ngoài quyền quản lý của Lab 5.2 nhưng Metrics API chưa sẵn sàng.
    exit /b 1
  )
) else (
  echo [Lab 5.2] Metrics API chưa có; cài Metrics Server v0.9.0 cho local cluster...
  kubectl apply --dry-run=server -f "%METRICS_MANIFEST%"
  if errorlevel 1 exit /b 1
  kubectl apply -f "%METRICS_MANIFEST%"
  if errorlevel 1 exit /b 1
)
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s
if errorlevel 1 exit /b 1
for /l %%T in (1,1,60) do (
  kubectl top nodes >nul 2>&1
  if not errorlevel 1 (
    echo [Lab 5.2] Metrics API đã sẵn sàng.
    exit /b 0
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Metrics API chưa sẵn sàng sau thời gian chờ.
exit /b 1

:resolve_pod
set "POD="
for /f "tokens=2 delims=/" %%P in ('kubectl get pods -n "%NS%" -l "lab=5.1" -o name') do set "POD=%%P"
if not defined POD (
  echo [ERROR] Không tìm thấy Pod Lab 5.1.
  exit /b 1
)
exit /b 0

:show_logs
echo.
echo [Lab 5.2] Current log của container health-api:
kubectl logs "%POD%" -n "%NS%" -c health-api --tail=20
if errorlevel 1 exit /b 1
echo.
echo [Lab 5.2] Log container readiness-reporter bằng -c:
kubectl logs "%POD%" -n "%NS%" -c readiness-reporter --tail=20
if errorlevel 1 exit /b 1
echo.
echo [Lab 5.2] Log instance health-api trước lần restart:
kubectl logs "%POD%" -n "%NS%" -c health-api --previous --tail=30
exit /b %errorlevel%

:show_events
echo.
echo [Lab 5.2] kubectl describe Pod, gồm Events ở cuối:
kubectl describe pod "%POD%" -n "%NS%"
if errorlevel 1 exit /b 1
echo.
echo [Lab 5.2] Events theo thứ tự thời gian:
kubectl get events -n "%NS%" --field-selector "involvedObject.name=%POD%" --sort-by=.metadata.creationTimestamp
exit /b %errorlevel%

:show_top
echo.
echo [Lab 5.2] Resource usage từng container:
for /l %%T in (1,1,45) do (
  kubectl top pod "%POD%" -n "%NS%" --containers >nul 2>&1
  if not errorlevel 1 (
    kubectl top pod "%POD%" -n "%NS%" --containers
    echo.
    kubectl top node
    exit /b !errorlevel!
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Chưa có metrics sample cho Pod %POD%.
exit /b 1

:verify
set "RESTARTS="
for /f "delims=" %%R in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.status.containerStatuses[?(@.name=='health-api')].restartCount}"') do set "RESTARTS=%%R"
echo health_api_restarts=!RESTARTS!
if not defined RESTARTS exit /b 1
if !RESTARTS! LSS 1 (
  echo [ERROR] Chưa có previous container instance để quan sát.
  exit /b 1
)
kubectl logs "%POD%" -n "%NS%" -c health-api --previous --tail=1 >nul
if errorlevel 1 exit /b 1
kubectl get events -n "%NS%" --field-selector "involvedObject.name=%POD%" -o jsonpath="{range .items[*]}{.reason}{'\n'}{end}" | findstr /I "Unhealthy" >nul
if errorlevel 1 (
  echo [ERROR] Không tìm thấy Event reason Unhealthy.
  exit /b 1
)
kubectl get events -n "%NS%" --field-selector "involvedObject.name=%POD%" -o jsonpath="{range .items[*]}{.reason}{'\n'}{end}" | findstr /I "Killing" >nul
if errorlevel 1 (
  echo [ERROR] Không tìm thấy Event reason Killing.
  exit /b 1
)
kubectl top pod "%POD%" -n "%NS%" --containers >nul
if errorlevel 1 exit /b 1
echo previous_log=available
echo unhealthy_event=present
echo killing_event=present
echo pod_metrics=available
exit /b 0

:usage
echo Usage: %~nx0 [run^|prepare^|restart^|logs^|events^|top^|verify^|cleanup^|cleanup-metrics^|help]
echo.
echo   run              Prepare, restart health-api and inspect all signals.
echo   prepare          Deploy Lab 5.1 workload and ensure Metrics API.
echo   restart          Trigger a real liveness-driven container restart.
echo   logs             Show current, sidecar and --previous logs.
echo   events           Show describe output and chronologically sorted Events.
echo   top              Show kubectl top for Pod containers and node.
echo   verify           Assert previous logs, Events and metrics are present.
echo   cleanup          Delete the observability workload only.
echo   cleanup-metrics  Remove Metrics Server only when owned by Lab 5.2.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 5.2 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl get apiservice v1beta1.metrics.k8s.io
echo Gợi ý: kubectl get pods -n %NS% -l lab=5.1
exit /b 1
