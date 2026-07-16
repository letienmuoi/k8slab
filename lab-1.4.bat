@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "MANIFEST=lab-1.4-label-annotation.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="reset" goto :reset
if /I "%ACTION%"=="query" goto :query
if /I "%ACTION%"=="mutate" goto :mutate
if /I "%ACTION%"=="verify" goto :verify
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :reset_resources
if errorlevel 1 goto :fail
call :query_selectors
if errorlevel 1 goto :fail
call :mutate_labels
if errorlevel 1 goto :fail
call :verify_matrix
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 1.4 hoàn tất toàn bộ selector, bulk update, --overwrite và annotation drill.
echo Dùng "%~nx0 cleanup" để xóa sáu audit Pod.
exit /b 0

:reset
call :precheck
if errorlevel 1 goto :fail
call :reset_resources
if errorlevel 1 goto :fail
exit /b 0

:query
call :require_kubectl
if errorlevel 1 goto :fail
call :query_selectors
exit /b %errorlevel%

:mutate
call :require_kubectl
if errorlevel 1 goto :fail
call :mutate_labels
exit /b %errorlevel%

:verify
call :require_kubectl
if errorlevel 1 goto :fail
call :verify_matrix
exit /b %errorlevel%

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
kubectl delete pods -n "%NS%" -l lab=1.4 --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa đúng sáu audit Pod của Lab 1.4.
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 1.4] Kiểm tra Kafka, Flink, Iceberg REST và MinIO...
kubectl wait -n "%NS%" --for=condition=Available deployment/kafka --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-jobmanager --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-taskmanager --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/iceberg-rest --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/minio --timeout=30s
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

:reset_resources
echo.
echo [Lab 1.4] Reset và bulk-create sáu audit Pod nghiệp vụ thật...
kubectl delete pods -n "%NS%" -l lab=1.4 --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=jsonpath="{.status.phase}"=Succeeded pod -l lab=1.4 --timeout=180s
if errorlevel 1 exit /b 1
kubectl get pods -n "%NS%" -l lab=1.4 -L env,tier,track,component
echo.
echo [Lab 1.4] Output audit thật:
kubectl logs -n "%NS%" -l lab=1.4 --prefix=true --tail=80 --max-log-requests=6
exit /b %errorlevel%

:query_selectors
echo.
echo [Lab 1.4] Equality / inequality selectors:
kubectl get pods -n "%NS%" -l "lab=1.4,env=dev"
if errorlevel 1 exit /b 1
kubectl get pods -n "%NS%" -l "lab=1.4,env=prod,tier=serve"
if errorlevel 1 exit /b 1
kubectl get pods -n "%NS%" -l "lab=1.4,component=flink"
if errorlevel 1 exit /b 1
kubectl get pods -n "%NS%" -l "lab=1.4,env!=prod"
if errorlevel 1 exit /b 1

echo.
echo [Lab 1.4] Set-based selectors:
kubectl get pods -n "%NS%" -l "lab=1.4,component in (kafka,flink)"
if errorlevel 1 exit /b 1
kubectl get pods -n "%NS%" -l "lab=1.4,env in (dev,prod),tier notin (serve)"
if errorlevel 1 exit /b 1
kubectl get pods -n "%NS%" -l "lab=1.4,track"
exit /b %errorlevel%

:mutate_labels
kubectl get pods -n "%NS%" -l "lab=1.4,env=dev" --no-headers | findstr . >nul
if errorlevel 1 (
  echo [ERROR] Không còn Pod env=dev. Hãy chạy "%~nx0 reset" trước khi mutate.
  exit /b 1
)

echo.
echo [Lab 1.4] Thêm owner cho toàn bộ audit Pod...
kubectl label pods -n "%NS%" -l lab=1.4 owner=franc
if errorlevel 1 exit /b 1

echo.
echo [Lab 1.4] Cố ý đổi env mà không có --overwrite; lệnh này PHẢI thất bại...
kubectl label pods -n "%NS%" -l "lab=1.4,env=dev" env=test >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Lệnh thiếu --overwrite lại thành công ngoài dự kiến.
  exit /b 1
)
echo [EXPECTED] Kubernetes từ chối thay đổi label đã tồn tại.

echo [Lab 1.4] Chạy lại đúng với --overwrite...
kubectl label pods -n "%NS%" -l "lab=1.4,env=dev" env=test --overwrite
if errorlevel 1 exit /b 1
kubectl label pods -n "%NS%" -l "lab=1.4,tier in (ingest,process)" team=data
if errorlevel 1 exit /b 1
kubectl label pods -n "%NS%" -l "lab=1.4,track=stable" track=blue --overwrite
if errorlevel 1 exit /b 1
kubectl label pod audit-iceberg-tables-dev -n "%NS%" track-
if errorlevel 1 exit /b 1

echo.
echo [Lab 1.4] Annotation add rồi overwrite...
kubectl annotate pods -n "%NS%" -l lab=1.4 lab.muoilt.vn/owner=franc
if errorlevel 1 exit /b 1
kubectl annotate pods -n "%NS%" -l lab=1.4 lab.muoilt.vn/owner=franc-nguyen --overwrite
exit /b %errorlevel%

:verify_matrix
echo.
echo [Lab 1.4] Assertions số object theo selector:
call :assert_count "lab=1.4,env=prod,tier=serve" 1
if errorlevel 1 exit /b 1
call :assert_count "lab=1.4,env=test" 3
if errorlevel 1 exit /b 1
call :assert_count "lab=1.4,team=data" 4
if errorlevel 1 exit /b 1
call :assert_count "lab=1.4,!track" 1
if errorlevel 1 exit /b 1

echo.
echo [Lab 1.4] Ma trận label cuối:
kubectl get pods -n "%NS%" -l lab=1.4 -L env,tier,track,component,owner,team
if errorlevel 1 exit /b 1
echo.
echo [Lab 1.4] Annotation owner:
kubectl get pods -n "%NS%" -l lab=1.4 -o custom-columns="NAME:.metadata.name,OWNER:.metadata.annotations.lab\.muoilt\.vn/owner"
exit /b %errorlevel%

:assert_count
set "ACTUAL="
for /f %%C in ('kubectl get pods -n "%NS%" -l "%~1" --no-headers 2^>nul ^| find /c /v ""') do set "ACTUAL=%%C"
if not defined ACTUAL set "ACTUAL=0"
echo   selector=[%~1] expected=%~2 actual=%ACTUAL%
if not "%ACTUAL%"=="%~2" exit /b 1
exit /b 0

:usage
echo Usage: %~nx0 [run^|reset^|query^|mutate^|verify^|cleanup^|help]
echo.
echo   run      Reset Pods and execute the full label/annotation drill.
echo   reset    Recreate the six audit Pods with original labels.
echo   query    Run equality, inequality and set-based selectors.
echo   mutate   Run bulk label, expected overwrite failure and annotation updates.
echo   verify   Assert final selector counts and print the final matrix.
echo   cleanup  Delete only Pods selected by lab=1.4.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 1.4 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl get pods -n %NS% -l lab=1.4 --show-labels
exit /b 1
