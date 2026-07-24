@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "DEPLOY=pipeline-normalizer-api"
set "HPA=pipeline-normalizer-api"
set "JOB=pipeline-normalizer-load"
set "APP_MANIFEST=lab-2.3-normalizer.yaml"
set "HPA_MANIFEST=lab-2.3-hpa.yaml"
set "LOAD_MANIFEST=lab-2.3-load-job.yaml"
set "METRICS_MANIFEST=lab-2.3-metrics-server.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="deploy" goto :deploy_action
if /I "%ACTION%"=="scale10" goto :scale_action
if /I "%ACTION%"=="hpa" goto :hpa_action
if /I "%ACTION%"=="load" goto :load_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="cleanup-metrics" goto :cleanup_metrics
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :deploy_app
if errorlevel 1 goto :fail
call :manual_scale_10
if errorlevel 1 goto :fail
call :create_hpa
if errorlevel 1 goto :fail
call :start_load
if errorlevel 1 goto :fail
call :wait_hpa_active
if errorlevel 1 goto :fail
call :observe_load
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 2.3 hoàn tất: manual scale 10 và HPA CPU target 50%% đã được kiểm chứng.
echo Dùng "%~nx0 cleanup" để xóa workload; Metrics Server được giữ lại.
exit /b 0

:deploy_action
call :precheck
if errorlevel 1 goto :fail
call :deploy_app
if errorlevel 1 goto :fail
exit /b 0

:scale_action
call :require_deployment
if errorlevel 1 goto :fail
call :manual_scale_10
if errorlevel 1 goto :fail
exit /b 0

:hpa_action
call :precheck
if errorlevel 1 goto :fail
call :require_deployment
if errorlevel 1 goto :fail
call :create_hpa
if errorlevel 1 goto :fail
call :wait_hpa_active
if errorlevel 1 goto :fail
call :show_state
exit /b %errorlevel%

:load_action
call :precheck
if errorlevel 1 goto :fail
call :require_deployment
if errorlevel 1 goto :fail
kubectl get hpa "%HPA%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có HPA. Hãy chạy "%~nx0 hpa" trước.
  exit /b 1
)
call :start_load
if errorlevel 1 goto :fail
call :observe_load
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_deployment
if errorlevel 1 goto :fail
call :show_state
exit /b %errorlevel%

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
kubectl delete -f "%LOAD_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete -f "%HPA_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete -f "%APP_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete pods -n "%NS%" -l lab=2.3 --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa Deployment, Service, HPA, load Job và Pods của Lab 2.3.
echo Metrics Server được giữ vì là cluster add-on.
exit /b 0

:cleanup_metrics
call :require_kubectl
if errorlevel 1 goto :fail
kubectl get deployment metrics-server -n kube-system >nul 2>&1
if errorlevel 1 (
  echo [OK] Metrics Server không tồn tại.
  exit /b 0
)
set "METRICS_OWNER="
for /f "delims=" %%O in ('kubectl get deployment metrics-server -n kube-system -o jsonpath^="{.metadata.annotations.lab\.muoilt\.vn/managed-by}"') do set "METRICS_OWNER=%%O"
if not "%METRICS_OWNER%"=="lab-2.3" (
  echo [ERROR] Metrics Server không do Lab 2.3 quản lý; từ chối xóa.
  exit /b 1
)
kubectl delete -f "%METRICS_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa Metrics Server do Lab 2.3 cài đặt.
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 2.3] Kiểm tra Flink và Metrics API...
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-taskmanager --timeout=30s
if errorlevel 1 exit /b 1
call :ensure_metrics
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

:require_deployment
call :require_kubectl
if errorlevel 1 exit /b 1
kubectl get deployment "%DEPLOY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy deployment/%DEPLOY%. Hãy chạy "%~nx0 deploy" trước.
  exit /b 1
)
exit /b 0

:ensure_metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes >nul 2>&1
if not errorlevel 1 (
  echo [Lab 2.3] Metrics API đã hoạt động.
  exit /b 0
)
echo [Lab 2.3] Metrics API chưa có; cài Metrics Server v0.9.0 cho local cluster...
kubectl apply -f "%METRICS_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s
if errorlevel 1 exit /b 1
for /l %%T in (1,1,60) do (
  kubectl top nodes >nul 2>&1
  if not errorlevel 1 (
    echo [Lab 2.3] Metrics API đã sẵn sàng.
    exit /b 0
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Metrics API chưa sẵn sàng sau thời gian chờ.
exit /b 1

:deploy_app
echo.
echo [Lab 2.3] Reset và deploy hai Normalizer API Pods...
kubectl delete -f "%LOAD_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete -f "%HPA_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete -f "%APP_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete pods -n "%NS%" -l lab=2.3 --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%APP_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=180s
if errorlevel 1 exit /b 1
echo [Lab 2.3] Response normalization thật:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://pipeline-normalizer:8080/normalize?line=%%20%%20DU%%20%%20%%20LIEU%%09AI%%20%%20"
exit /b %errorlevel%

:manual_scale_10
echo.
echo [Lab 2.3] Xóa HPA trước khi manual scale...
kubectl delete hpa "%HPA%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
echo [Lab 2.3] Manual scale Deployment lên 10 replica...
kubectl scale deployment/%DEPLOY% -n "%NS%" --replicas=10
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=180s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=jsonpath="{.status.readyReplicas}"=10 deployment/%DEPLOY% --timeout=180s
if errorlevel 1 exit /b 1
set "SPEC_REPLICAS="
for /f "delims=" %%R in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.replicas}"') do set "SPEC_REPLICAS=%%R"
echo expected_replicas=10
echo actual_replicas=%SPEC_REPLICAS%
if not "%SPEC_REPLICAS%"=="10" exit /b 1
kubectl get deployment "%DEPLOY%" -n "%NS%"
kubectl get pods -n "%NS%" -l "lab=2.3,component=normalizer-api"
exit /b %errorlevel%

:create_hpa
echo.
echo [Lab 2.3] Configure HPA min=2 max=10 CPU target=50%%...
kubectl apply -f "%HPA_MANIFEST%"
if errorlevel 1 exit /b 1
set "CPU_TARGET="
for /f "delims=" %%C in ('kubectl get hpa "%HPA%" -n "%NS%" -o jsonpath^="{.spec.metrics[0].resource.target.averageUtilization}"') do set "CPU_TARGET=%%C"
echo expected_cpu_target=50
echo actual_cpu_target=%CPU_TARGET%
if not "%CPU_TARGET%"=="50" exit /b 1
exit /b 0

:wait_hpa_active
echo [Lab 2.3] Chờ HPA nhận CPU metrics...
kubectl wait -n "%NS%" --for=condition=ScalingActive hpa/%HPA% --timeout=180s
exit /b %errorlevel%

:start_load
echo.
echo [Lab 2.3] Khởi động Job gửi normalization workload thật trong 90 giây...
kubectl delete job "%JOB%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%LOAD_MANIFEST%"
exit /b %errorlevel%

:observe_load
echo [Lab 2.3] Chờ Metrics Server lấy mẫu CPU dưới tải...
ping -n 31 127.0.0.1 >nul
echo.
echo [Lab 2.3] HPA dưới tải:
kubectl get hpa "%HPA%" -n "%NS%"
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.3] CPU từng normalizer Pod:
call :wait_pod_metrics
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=complete job/%JOB% --timeout=180s
if errorlevel 1 exit /b 1
kubectl logs job/%JOB% -n "%NS%"
if errorlevel 1 exit /b 1
call :show_state
exit /b %errorlevel%

:wait_pod_metrics
for /l %%M in (1,1,60) do (
  kubectl top pods -n "%NS%" -l "lab=2.3,component=normalizer-api" >nul 2>&1
  if not errorlevel 1 (
    kubectl top pods -n "%NS%" -l "lab=2.3,component=normalizer-api"
    exit /b 0
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Pod CPU metrics chưa sẵn sàng sau thời gian chờ.
exit /b 1

:show_state
echo.
echo [Lab 2.3] Deployment:
kubectl get deployment "%DEPLOY%" -n "%NS%"
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.3] HPA:
kubectl get hpa "%HPA%" -n "%NS%"
if errorlevel 1 (
  echo [WARN] HPA chưa tồn tại.
) else (
  kubectl describe hpa "%HPA%" -n "%NS%"
)
echo.
echo [Lab 2.3] Pods:
kubectl get pods -n "%NS%" -l lab=2.3 -L component
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|deploy^|scale10^|hpa^|load^|verify^|cleanup^|cleanup-metrics^|help]
echo.
echo   run              Execute deploy, manual scale 10, HPA 50%% and real CPU load.
echo   deploy           Ensure Metrics API and deploy two Normalizer API Pods.
echo   scale10          Delete HPA, then manually scale Deployment to 10 replicas.
echo   hpa              Configure min=2, max=10, target CPU=50%% and wait for metrics.
echo   load             Run the 90-second normalization load Job and show CPU metrics.
echo   verify           Show Deployment, HPA and Lab 2.3 Pods.
echo   cleanup          Delete Lab 2.3 workload but keep Metrics Server.
echo   cleanup-metrics  Delete Metrics Server only when marked as managed by Lab 2.3.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 2.3 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl get deployment,hpa,pod,job -n %NS% -l lab=2.3
echo Gợi ý: kubectl top pods -n %NS%
exit /b 1
