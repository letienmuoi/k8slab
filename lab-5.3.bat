@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "DEPLOY=pipeline-triage"
set "SERVICE=pipeline-triage"
set "SOURCE=lab-5.3-app-source.yaml"
set "BROKEN=lab-5.3-broken.yaml"
set "SELECTOR_FIXED=lab-5.3-selector-fixed.yaml"
set "FIXED=lab-5.3-fixed.yaml"
set "GOOD_IMAGE=mualanhlung017/ai-data-pipeline:1.0.2"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="selector" goto :selector_action
if /I "%ACTION%"=="runtime" goto :runtime_action
if /I "%ACTION%"=="fix-image" goto :fix_image_action
if /I "%ACTION%"=="fix-port" goto :fix_port_action
if /I "%ACTION%"=="solution" goto :solution_action
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
call :diagnose_selector
if errorlevel 1 goto :fail
call :deploy_runtime_broken
if errorlevel 1 goto :fail
call :fix_image
if errorlevel 1 goto :fail
call :diagnose_target_port
if errorlevel 1 goto :fail
call :fix_target_port
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 5.3 hoàn tất: selector, image name và targetPort đều đã triage theo đúng thứ tự.
exit /b 0

:selector_action
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
call :diagnose_selector
if errorlevel 1 goto :fail
exit /b 0

:runtime_action
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
call :deploy_runtime_broken
if errorlevel 1 goto :fail
exit /b 0

:fix_image_action
call :require_workload
if errorlevel 1 goto :fail
call :fix_image
if errorlevel 1 goto :fail
call :diagnose_target_port
if errorlevel 1 goto :fail
exit /b 0

:fix_port_action
call :require_workload
if errorlevel 1 goto :fail
call :fix_target_port
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:solution_action
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_lab
if errorlevel 1 goto :fail
kubectl apply --dry-run=server -f "%SOURCE%" -f "%FIXED%"
if errorlevel 1 goto :fail
kubectl apply -f "%SOURCE%" -f "%FIXED%"
if errorlevel 1 goto :fail
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=180s
if errorlevel 1 goto :fail
call :verify
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
echo [OK] Đã xóa toàn bộ resource Lab 5.3.
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
exit /b %errorlevel%

:require_workload
call :require_kubectl
if errorlevel 1 exit /b 1
kubectl get deployment "%DEPLOY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có deployment/%DEPLOY%. Chạy "%~nx0 runtime" trước.
  exit /b 1
)
exit /b 0

:reset_lab
kubectl delete deployment "%DEPLOY%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete service "%SERVICE%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete configmap pipeline-triage-source -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete pod -n "%NS%" -l lab=5.3 --ignore-not-found --wait=true
exit /b %errorlevel%

:diagnose_selector
echo.
echo [Lab 5.3] Stage 1 - API server phải từ chối Deployment selector mismatch...
set "ERROR_FILE=%TEMP%\lab-5.3-selector-!RANDOM!.txt"
kubectl apply --dry-run=server -f "%BROKEN%" > "!ERROR_FILE!" 2>&1
if not errorlevel 1 (
  type "!ERROR_FILE!"
  del /q "!ERROR_FILE!" >nul 2>&1
  echo [ERROR] Broken selector được API server chấp nhận ngoài dự kiến.
  exit /b 1
)
type "!ERROR_FILE!"
findstr /I /C:"does not match template" "!ERROR_FILE!" >nul
if errorlevel 1 (
  del /q "!ERROR_FILE!" >nul 2>&1
  echo [ERROR] Lỗi không phải Deployment selector mismatch mong đợi.
  exit /b 1
)
del /q "!ERROR_FILE!" >nul 2>&1
echo selector_mismatch=rejected_as_expected
exit /b 0

:deploy_runtime_broken
echo.
echo [Lab 5.3] Stage 2 - selector đã sửa, chờ kubelet báo InvalidImageName...
kubectl apply --dry-run=server -f "%SOURCE%" -f "%SELECTOR_FIXED%"
if errorlevel 1 exit /b 1
kubectl apply -f "%SOURCE%" -f "%SELECTOR_FIXED%"
if errorlevel 1 exit /b 1
for /l %%T in (1,1,60) do (
  call :resolve_pod
  if defined POD (
    set "WAIT_REASON="
    for /f "delims=" %%R in ('kubectl get pod "!POD!" -n "%NS%" -o jsonpath^="{.status.containerStatuses[?(@.name=='gateway')].state.waiting.reason}" 2^>nul') do set "WAIT_REASON=%%R"
    if "!WAIT_REASON!"=="InvalidImageName" (
      echo pod=!POD!
      echo image_wait_reason=!WAIT_REASON!
      kubectl get pod "!POD!" -n "%NS%" -o wide
      exit /b 0
    )
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Không quan sát được InvalidImageName.
kubectl get pods -n "%NS%" -l lab=5.3
exit /b 1

:resolve_pod
set "POD="
for /f "tokens=2 delims=/" %%P in ('kubectl get pods -n "%NS%" -l "lab=5.3" -o name 2^>nul') do set "POD=%%P"
exit /b 0

:fix_image
echo.
echo [Lab 5.3] Stage 3 - sửa image reference về tên và tag hợp lệ...
kubectl set image deployment/%DEPLOY% -n "%NS%" "gateway=%GOOD_IMAGE%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=180s
if errorlevel 1 exit /b 1
set "IMAGE_NOW="
for /f "delims=" %%I in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[?(@.name=='gateway')].image}"') do set "IMAGE_NOW=%%I"
echo image_after_fix=!IMAGE_NOW!
if not "!IMAGE_NOW!"=="%GOOD_IMAGE%" exit /b 1
exit /b 0

:diagnose_target_port
echo.
echo [Lab 5.3] Stage 4 - Pod Ready nhưng Service targetPort vẫn sai...
set "TARGET_PORT="
for /f "delims=" %%P in ('kubectl get service "%SERVICE%" -n "%NS%" -o jsonpath^="{.spec.ports[0].targetPort}"') do set "TARGET_PORT=%%P"
echo service_target_port=!TARGET_PORT!
if not "!TARGET_PORT!"=="9099" exit /b 1
kubectl get endpointslice -n "%NS%" -l "kubernetes.io/service-name=%SERVICE%" -o wide
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 4 "http://%SERVICE%:8080/api" >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Service request thành công dù targetPort đang là 9099.
  exit /b 1
)
echo service_request=failed_as_expected
exit /b 0

:fix_target_port
echo.
echo [Lab 5.3] Stage 5 - patch Service targetPort về cổng container 8080...
kubectl patch service "%SERVICE%" -n "%NS%" --type=merge -p "{\"spec\":{\"ports\":[{\"name\":\"http\",\"port\":8080,\"protocol\":\"TCP\",\"targetPort\":8080}]}}"
if errorlevel 1 exit /b 1
for /l %%T in (1,1,30) do (
  kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 4 "http://%SERVICE%:8080/ready" >nul 2>&1
  if not errorlevel 1 (
    echo service_after_fix=ready
    exit /b 0
  )
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Service chưa hoạt động sau khi sửa targetPort.
exit /b 1

:verify
set "SELECTOR="
set "IMAGE_NOW="
set "TARGET_PORT="
for /f "delims=" %%S in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.selector.matchLabels.component}"') do set "SELECTOR=%%S"
for /f "delims=" %%I in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[?(@.name=='gateway')].image}"') do set "IMAGE_NOW=%%I"
for /f "delims=" %%P in ('kubectl get service "%SERVICE%" -n "%NS%" -o jsonpath^="{.spec.ports[0].targetPort}"') do set "TARGET_PORT=%%P"
echo deployment_selector=!SELECTOR!
echo deployment_image=!IMAGE_NOW!
echo service_target_port=!TARGET_PORT!
if not "!SELECTOR!"=="triage-api" exit /b 1
if not "!IMAGE_NOW!"=="%GOOD_IMAGE%" exit /b 1
if not "!TARGET_PORT!"=="8080" exit /b 1
echo.
echo [Lab 5.3] Business response qua Service đã sửa:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%SERVICE%:8080/api"
if errorlevel 1 exit /b 1
kubectl get deployment,service,endpointslice -n "%NS%" -l lab=5.3
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|selector^|runtime^|fix-image^|fix-port^|solution^|verify^|cleanup^|help]
echo.
echo   run        Diagnose and fix all three defects in sequence.
echo   selector   Require API rejection for selector mismatch.
echo   runtime    Apply selector-fixed state and observe InvalidImageName.
echo   fix-image  Fix the image and prove targetPort is still broken.
echo   fix-port   Patch targetPort to 8080 and verify real traffic.
echo   solution   Deploy the fully fixed reference manifest directly.
echo   verify     Verify selector, image, targetPort and Flink response.
echo   cleanup    Delete all Lab 5.3 resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 5.3 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl get pods -n %NS% -l lab=5.3
echo Gợi ý: kubectl describe deployment/%DEPLOY% -n %NS%
echo Gợi ý: kubectl get service,endpointslice -n %NS% -l lab=5.3
exit /b 1
