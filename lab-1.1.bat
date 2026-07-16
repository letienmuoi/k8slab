@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "POD=pod-60"
set "GENERATED=pod-60.generated.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="generate" goto :generate
if /I "%ACTION%"=="verify" goto :verify
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :write_manifest
if errorlevel 1 goto :fail

echo.
echo [Lab 1.1] Reset Pod cũ và tạo Pod từ manifest dry-run...
kubectl delete pod "%POD%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl create -f "%GENERATED%"
if errorlevel 1 goto :fail
kubectl wait -n "%NS%" --for=condition=Ready pod/%POD% --timeout=60s
if errorlevel 1 goto :fail

call :show_spec
if errorlevel 1 goto :fail

echo.
echo [Lab 1.1] Chờ Pod hoàn tất cửa sổ giám sát 60 giây...
kubectl wait -n "%NS%" --for=jsonpath="{.status.phase}"=Succeeded pod/%POD% --timeout=90s
if errorlevel 1 goto :fail

echo.
echo [Lab 1.1] Kết quả cuối:
kubectl get pod "%POD%" -n "%NS%" -L app,lab,component
kubectl get pod "%POD%" -n "%NS%" -o custom-columns="REASON:.status.containerStatuses[0].state.terminated.reason,EXIT_CODE:.status.containerStatuses[0].state.terminated.exitCode,RESTARTS:.status.containerStatuses[0].restartCount"
echo.
echo [Lab 1.1] Sáu snapshot Flink thật:
kubectl logs "%POD%" -n "%NS%"
if errorlevel 1 goto :fail

echo.
echo [OK] Lab 1.1 hoàn tất. Chạy "%~nx0 cleanup" để xóa Pod.
exit /b 0

:generate
call :precheck
if errorlevel 1 goto :fail
call :write_manifest
if errorlevel 1 goto :fail
echo.
echo [OK] Đã export: %GENERATED%
exit /b 0

:verify
call :require_kubectl
if errorlevel 1 goto :fail
kubectl get pod "%POD%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy pod/%POD% trong namespace %NS%.
  exit /b 1
)
call :show_spec
if errorlevel 1 goto :fail
echo.
echo [Lab 1.1] Trạng thái và log hiện tại:
kubectl get pod "%POD%" -n "%NS%" -L app,lab,component
kubectl logs "%POD%" -n "%NS%" --tail=10
exit /b %errorlevel%

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
kubectl delete pod "%POD%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa tài nguyên Lab 1.1. File %GENERATED% được giữ để anh kiểm tra dry-run.
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 1.1] Kiểm tra Flink thật...
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-jobmanager --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-taskmanager --timeout=30s
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

:write_manifest
echo.
echo [Lab 1.1] Export Pod imperatively bằng --dry-run=client -o yaml...
kubectl run "%POD%" ^
  --namespace="%NS%" ^
  --image=mualanhlung017/ai-data-pipeline:1.0.2 ^
  --image-pull-policy=IfNotPresent ^
  --restart=Never ^
  --labels=app=ai-data-pipeline,lab=1.1,component=flink-monitor ^
  --annotations=lab.muoilt.vn/purpose=monitor-flink-for-60-seconds ^
  --env=APP_ENV=lab ^
  --env=OWNER=franc ^
  --env=CHECK_TARGET=http://flink-jobmanager:8081/jobs/overview ^
  --env=CHECK_INTERVAL_SECONDS=10 ^
  --env=MONITOR_DURATION_SECONDS=60 ^
  --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"pod-60\",\"resources\":{\"requests\":{\"cpu\":\"25m\",\"memory\":\"32Mi\"},\"limits\":{\"cpu\":\"100m\",\"memory\":\"128Mi\"}}}]}}" ^
  --override-type=strategic ^
  --dry-run=client -o yaml ^
  --command -- /usr/bin/bash -ec "deadline=$((SECONDS + MONITOR_DURATION_SECONDS)); while (( SECONDS < deadline )); do /usr/bin/curl -fsS \"$CHECK_TARGET\"; printf \"\\n\"; /usr/bin/sleep \"$CHECK_INTERVAL_SECONDS\"; done" > "%GENERATED%"
if errorlevel 1 exit /b 1
kubectl create --dry-run=client -f "%GENERATED%"
exit /b %errorlevel%

:show_spec
echo.
echo [Lab 1.1] Exam-speed verification:
kubectl get pod "%POD%" -n "%NS%" --show-labels
if errorlevel 1 exit /b 1
echo Labels:
kubectl get pod "%POD%" -n "%NS%" -o jsonpath="{.metadata.labels}"
echo.
echo Environment:
kubectl get pod "%POD%" -n "%NS%" -o jsonpath="{.spec.containers[0].env}"
echo.
echo Resources:
kubectl get pod "%POD%" -n "%NS%" -o jsonpath="{.spec.containers[0].resources}"
echo.
echo Restart policy:
kubectl get pod "%POD%" -n "%NS%" -o jsonpath="{.spec.restartPolicy}"
echo.
exit /b 0

:usage
echo Usage: %~nx0 [run^|generate^|verify^|cleanup^|help]
echo.
echo   run       Export manifest, create Pod, wait 60 seconds and show real Flink logs.
echo   generate  Only export %GENERATED% with kubectl dry-run.
echo   verify    Show labels, env, resources, status and logs of the existing Pod.
echo   cleanup   Delete only pod/%POD% from namespace %NS%.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
goto :usage_error

:usage_error
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 1.1 dừng vì một lệnh thất bại.
exit /b 1
