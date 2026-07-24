@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "DEPLOY=pipeline-release-auditor"
set "MANIFEST=lab-2.1-rolling-update.yaml"
set "V1=mualanhlung017/ai-data-pipeline:1.0.1"
set "V2=mualanhlung017/ai-data-pipeline:1.0.2"
set "BAD=mualanhlung017/ai-data-pipeline:ckad-bad-does-not-exist"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="deploy" goto :deploy_action
if /I "%ACTION%"=="update" goto :update_action
if /I "%ACTION%"=="bad" goto :bad_action
if /I "%ACTION%"=="rollback" goto :rollback_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :deploy_v1
if errorlevel 1 goto :fail
call :update_v2
if errorlevel 1 goto :fail
call :deploy_bad
if errorlevel 1 goto :fail
call :rollback_v2
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 2.1 hoàn tất: v1 -^> v2 -^> bad release -^> rollback v2.
echo Dùng "%~nx0 cleanup" để xóa Deployment của lab.
exit /b 0

:deploy_action
call :precheck
if errorlevel 1 goto :fail
call :deploy_v1
if errorlevel 1 goto :fail
exit /b 0

:update_action
call :require_deployment
if errorlevel 1 goto :fail
call :update_v2
if errorlevel 1 goto :fail
exit /b 0

:bad_action
call :require_deployment
if errorlevel 1 goto :fail
call :deploy_bad
if errorlevel 1 goto :fail
echo [OK] Bad release được giữ lại để anh quan sát. Chạy "%~nx0 rollback" khi sẵn sàng.
exit /b 0

:rollback_action
call :require_deployment
if errorlevel 1 goto :fail
call :rollback_v2
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
kubectl delete deployment "%DEPLOY%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete pods -n "%NS%" -l lab=2.1 --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa Deployment, ReplicaSets và Pods của Lab 2.1.
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 2.1] Kiểm tra dependency thật...
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

:require_deployment
call :require_kubectl
if errorlevel 1 exit /b 1
kubectl get deployment "%DEPLOY%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy deployment/%DEPLOY%. Hãy chạy "%~nx0 deploy" trước.
  exit /b 1
)
exit /b 0

:deploy_v1
echo.
echo [Lab 2.1] Reset và deploy v1: %V1%
kubectl delete deployment "%DEPLOY%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete pods -n "%NS%" -l lab=2.1 --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=120s
if errorlevel 1 exit /b 1
ping -n 6 127.0.0.1 >nul
call :assert_image "%V1%"
if errorlevel 1 exit /b 1
call :show_state
exit /b %errorlevel%

:update_v2
echo.
echo [Lab 2.1] Rolling update v1 -^> v2: %V2%
kubectl set image deployment/%DEPLOY% auditor=%V2% -n "%NS%"
if errorlevel 1 exit /b 1
kubectl annotate deployment "%DEPLOY%" -n "%NS%" "kubernetes.io/change-cause=Rolling update auditor from 1.0.1 to 1.0.2" --overwrite
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=120s
if errorlevel 1 exit /b 1
ping -n 13 127.0.0.1 >nul
call :assert_image "%V2%"
if errorlevel 1 exit /b 1
call :show_state
exit /b %errorlevel%

:deploy_bad
echo.
echo [Lab 2.1] Simulate bad deployment: %BAD%
kubectl set image deployment/%DEPLOY% auditor=%BAD% -n "%NS%"
if errorlevel 1 exit /b 1
kubectl annotate deployment "%DEPLOY%" -n "%NS%" "kubernetes.io/change-cause=Simulate bad release with missing image" --overwrite
if errorlevel 1 exit /b 1
echo [Lab 2.1] rollout status sau đây PHẢI timeout...
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=25s 2>nul
if not errorlevel 1 (
  echo [ERROR] Bad deployment lại rollout thành công ngoài dự kiến.
  exit /b 1
)
echo [EXPECTED] Rollout không hoàn thành vì image tag không tồn tại.
call :assert_image "%BAD%"
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.1] Ba replica v2 vẫn Available; Pod surge bị ImagePullBackOff:
kubectl get deployment "%DEPLOY%" -n "%NS%"
kubectl get pods -n "%NS%" -l lab=2.1 -o wide
kubectl get rs -n "%NS%" -l lab=2.1
exit /b %errorlevel%

:rollback_v2
echo.
echo [Lab 2.1] Rollback bad release về revision trước...
kubectl rollout history deployment/%DEPLOY% -n "%NS%"
if errorlevel 1 exit /b 1
kubectl rollout undo deployment/%DEPLOY% -n "%NS%" 2>nul
if errorlevel 1 exit /b 1
kubectl annotate deployment "%DEPLOY%" -n "%NS%" "kubernetes.io/change-cause=Rollback missing image to ai-data-pipeline:1.0.2" --overwrite
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=120s
if errorlevel 1 exit /b 1
ping -n 13 127.0.0.1 >nul
call :assert_image "%V2%"
if errorlevel 1 exit /b 1
call :show_state
exit /b %errorlevel%

:assert_image
set "ACTUAL_IMAGE="
for /f "delims=" %%I in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[0].image}"') do set "ACTUAL_IMAGE=%%I"
echo expected_image=%~1
echo actual_image=%ACTUAL_IMAGE%
if not "%ACTUAL_IMAGE%"=="%~1" (
  echo [ERROR] Deployment image không đúng kỳ vọng.
  exit /b 1
)
exit /b 0

:show_state
echo.
echo [Lab 2.1] Deployment:
kubectl get deployment "%DEPLOY%" -n "%NS%" -o wide
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.1] Pods và image thực tế:
kubectl get pods -n "%NS%" -l lab=2.1 -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[0].ready,PHASE:.status.phase,DELETING:.metadata.deletionTimestamp,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID"
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.1] ReplicaSets:
kubectl get rs -n "%NS%" -l lab=2.1
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.1] Rollout history:
kubectl rollout history deployment/%DEPLOY% -n "%NS%"
if errorlevel 1 exit /b 1
echo.
echo [Lab 2.1] Audit log thật:
kubectl logs -n "%NS%" -l lab=2.1 --prefix=true --tail=8 --max-log-requests=6 2>nul
if errorlevel 1 echo [WARN] Một Pod đang tạo/xóa nên chưa đọc được log của riêng Pod đó.
exit /b 0

:usage
echo Usage: %~nx0 [run^|deploy^|update^|bad^|rollback^|verify^|cleanup^|help]
echo.
echo   run       Execute v1, rolling update to v2, bad deployment and rollback.
echo   deploy    Reset and deploy release v1 (image 1.0.1).
echo   update    Rolling update the existing Deployment to v2 (image 1.0.2).
echo   bad       Deploy a missing image and keep the failed rollout for inspection.
echo   rollback  Roll back to the previous revision and verify image 1.0.2.
echo   verify    Show Deployment, Pods, ReplicaSets, history and real audit logs.
echo   cleanup   Delete only the Lab 2.1 Deployment and owned resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 2.1 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe deployment %DEPLOY% -n %NS%
echo Gợi ý: kubectl get pods,rs -n %NS% -l lab=2.1
exit /b 1
