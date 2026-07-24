@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "DEPLOY=pipeline-self-healing"
set "SERVICE=pipeline-self-healing"
set "MANIFEST=lab-5.1-self-healing.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="deploy" goto :deploy_action
if /I "%ACTION%"=="break" goto :break_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="status" goto :status_action
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
call :verify_healthy
if errorlevel 1 goto :fail
call :break_liveness
if errorlevel 1 goto :fail
call :verify_self_healed
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 5.1 hoàn tất: startup, readiness và liveness self-healing đều đã kiểm chứng.
exit /b 0

:deploy_action
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
call :deploy
if errorlevel 1 goto :fail
call :verify_healthy
if errorlevel 1 goto :fail
exit /b 0

:break_action
call :require_workload
if errorlevel 1 goto :fail
call :break_liveness
if errorlevel 1 goto :fail
call :verify_self_healed
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_workload
if errorlevel 1 goto :fail
call :verify_healthy
if errorlevel 1 goto :fail
exit /b 0

:status_action
call :require_workload
if errorlevel 1 goto :fail
call :show_status
exit /b %errorlevel%

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
echo [OK] Đã xóa workload Lab 5.1.
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
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-jobmanager --timeout=60s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/iceberg-rest --timeout=60s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/minio --timeout=60s
exit /b %errorlevel%

:require_workload
call :require_kubectl
if errorlevel 1 exit /b 1
kubectl get deployment "%DEPLOY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có deployment/%DEPLOY%. Chạy "%~nx0 deploy" trước.
  exit /b 1
)
exit /b 0

:reset_lab
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete pod -n "%NS%" -l lab=5.1 --ignore-not-found --wait=true
exit /b %errorlevel%

:deploy
echo.
echo [Lab 5.1] Validate và deploy self-healing business health API...
kubectl apply --dry-run=server -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=180s
if errorlevel 1 exit /b 1
call :resolve_pod
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready "pod/%POD%" --timeout=60s
exit /b %errorlevel%

:resolve_pod
set "POD="
for /f "tokens=2 delims=/" %%P in ('kubectl get pods -n "%NS%" -l "lab=5.1" -o name') do set "POD=%%P"
if not defined POD (
  echo [ERROR] Không tìm thấy Pod Lab 5.1.
  exit /b 1
)
exit /b 0

:verify_healthy
call :resolve_pod
if errorlevel 1 exit /b 1
echo.
echo [Lab 5.1] Probe configuration:
kubectl get pod "%POD%" -n "%NS%" -o jsonpath="{.spec.containers[?(@.name=='health-api')].startupProbe.httpGet.path}{'\n'}{.spec.containers[?(@.name=='health-api')].readinessProbe.exec.command}{'\n'}{.spec.containers[?(@.name=='health-api')].livenessProbe.httpGet.path}{'\n'}"
if errorlevel 1 exit /b 1
kubectl exec -n "%NS%" "%POD%" -c health-api -- /usr/bin/test -s /var/run/pipeline-health/ready
if errorlevel 1 (
  echo [ERROR] File readiness chưa tồn tại hoặc đang rỗng.
  exit /b 1
)
echo [Lab 5.1] Business snapshot qua Service:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%SERVICE%:8080/business"
if errorlevel 1 exit /b 1
set "READY_ENDPOINTS=0"
for /f "delims=" %%E in ('kubectl get endpointslice -n "%NS%" -l kubernetes.io/service-name^=%SERVICE% -o jsonpath^="{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{'\n'}{end}"') do set /a READY_ENDPOINTS+=1
echo ready_service_endpoints=!READY_ENDPOINTS!
if not "!READY_ENDPOINTS!"=="1" exit /b 1
call :show_status
exit /b %errorlevel%

:break_liveness
call :resolve_pod
if errorlevel 1 exit /b 1
set "RESTART_BEFORE="
for /f "delims=" %%R in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.status.containerStatuses[?(@.name=='health-api')].restartCount}"') do set "RESTART_BEFORE=%%R"
if not defined RESTART_BEFORE set "RESTART_BEFORE=0"
echo.
echo [Lab 5.1] Xóa liveness state file trong container health-api...
echo restart_count_before=!RESTART_BEFORE!
kubectl exec -n "%NS%" "%POD%" -c health-api -- /usr/bin/rm -f /var/run/pipeline-health/live
if errorlevel 1 exit /b 1
for /l %%T in (1,1,45) do (
  set "RESTART_NOW="
  for /f "delims=" %%R in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.status.containerStatuses[?(@.name=='health-api')].restartCount}" 2^>nul') do set "RESTART_NOW=%%R"
  if defined RESTART_NOW if !RESTART_NOW! GTR !RESTART_BEFORE! (
    echo restart_count_after=!RESTART_NOW!
    set "EXPECTED_RESTART=!RESTART_NOW!"
    exit /b 0
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Kubelet không restart health-api sau liveness failure.
exit /b 1

:verify_self_healed
call :resolve_pod
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready "pod/%POD%" --timeout=120s
if errorlevel 1 exit /b 1
set "RESTART_FINAL="
for /f "delims=" %%R in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.status.containerStatuses[?(@.name=='health-api')].restartCount}"') do set "RESTART_FINAL=%%R"
echo restart_count_final=!RESTART_FINAL!
if defined EXPECTED_RESTART if !RESTART_FINAL! LSS !EXPECTED_RESTART! exit /b 1
kubectl exec -n "%NS%" "%POD%" -c health-api -- /usr/bin/test -s /var/run/pipeline-health/ready
if errorlevel 1 exit /b 1
echo.
echo [Lab 5.1] Previous health-api log do kubelet giữ lại:
kubectl logs "%POD%" -n "%NS%" -c health-api --previous --tail=30
if errorlevel 1 exit /b 1
echo [Lab 5.1] Events self-healing:
kubectl get events -n "%NS%" --field-selector "involvedObject.name=%POD%" --sort-by=.metadata.creationTimestamp
exit /b %errorlevel%

:show_status
call :resolve_pod
if errorlevel 1 exit /b 1
kubectl get pod "%POD%" -n "%NS%" -o wide
if errorlevel 1 exit /b 1
kubectl get pod "%POD%" -n "%NS%" -o custom-columns="CONTAINER:.status.containerStatuses[*].name,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount"
if errorlevel 1 exit /b 1
echo [Lab 5.1] health-api current log:
kubectl logs "%POD%" -n "%NS%" -c health-api --tail=20
if errorlevel 1 exit /b 1
echo [Lab 5.1] readiness-reporter log:
kubectl logs "%POD%" -n "%NS%" -c readiness-reporter --tail=20
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|deploy^|break^|verify^|status^|cleanup^|help]
echo.
echo   run      Deploy, verify probes, break liveness and require recovery.
echo   deploy   Reset and deploy the business health API.
echo   break    Remove liveness state and require a container restart.
echo   verify   Verify file readiness, HTTP service and business snapshot.
echo   status   Show Pod status and both container logs.
echo   cleanup  Delete all Lab 5.1 resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 5.1 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe pods -n %NS% -l lab=5.1
echo Gợi ý: kubectl logs -n %NS% deployment/%DEPLOY% -c health-api
exit /b 1
