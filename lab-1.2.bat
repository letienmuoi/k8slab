@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "POD=pipeline-init-sidecar-demo"
set "MANIFEST=lab-1.2-init-sidecar.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="verify" goto :verify
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail

echo.
echo [Lab 1.2] Reset ConfigMap/Pod cũ rồi tạo init + app + sidecar...
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl apply -f "%MANIFEST%"
if errorlevel 1 goto :fail

echo.
echo [Lab 1.2] Chờ init container hoàn thành...
kubectl wait -n "%NS%" --for=condition=Initialized pod/%POD% --timeout=120s
if errorlevel 1 goto :fail
kubectl get pod "%POD%" -n "%NS%" -o jsonpath="initReason={.status.initContainerStatuses[0].state.terminated.reason}{' exitCode='}{.status.initContainerStatuses[0].state.terminated.exitCode}"
echo.

echo.
echo [Lab 1.2] Chờ app Flink SQL hoàn thành...
kubectl wait -n "%NS%" --for=jsonpath="{.status.containerStatuses[?(@.name=='app')].state.terminated.exitCode}"=0 pod/%POD% --timeout=240s
if errorlevel 1 goto :fail

call :show_results
if errorlevel 1 goto :fail

echo.
echo [OK] Lab 1.2 hoàn tất. Sidecar vẫn chạy đúng pattern; dùng "%~nx0 cleanup" để xóa Pod.
exit /b 0

:verify
call :require_kubectl
if errorlevel 1 goto :fail
kubectl get pod "%POD%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy pod/%POD% trong namespace %NS%.
  exit /b 1
)
call :show_results
exit /b %errorlevel%

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa ConfigMap, Pod và các emptyDir của Lab 1.2.
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 1.2] Kiểm tra Kafka và Flink thật...
kubectl wait -n "%NS%" --for=condition=Available deployment/kafka --timeout=30s
if errorlevel 1 exit /b 1
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

:show_results
echo.
echo [Lab 1.2] Trạng thái multi-container:
kubectl get pod "%POD%" -n "%NS%"
if errorlevel 1 exit /b 1
kubectl get pod "%POD%" -n "%NS%" -o jsonpath="{range .status.initContainerStatuses[*]}init/{.name}={.state}{' '}{end}{range .status.containerStatuses[*]}container/{.name}={.state}{' '}{end}"
echo.

echo.
echo [Lab 1.2] Dữ liệu init đã bàn giao qua emptyDir:
kubectl exec "%POD%" -n "%NS%" -c sidecar -- cat /work/input.txt
if errorlevel 1 exit /b 1

echo.
echo [Lab 1.2] Application log đọc qua sidecar:
kubectl logs "%POD%" -n "%NS%" -c sidecar --tail=120
if errorlevel 1 exit /b 1

echo.
echo [Lab 1.2] Record LAB12 đã qua LineNormalizer trong refined-data:
kubectl exec -n "%NS%" deployment/kafka -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic refined-data --from-beginning --timeout-ms 10000 2>nul | findstr /I "LAB12"
if errorlevel 1 echo [WARN] Chưa thấy LAB12; pipeline streaming có thể cần thêm vài giây để xử lý.
exit /b 0

:usage
echo Usage: %~nx0 [run^|verify^|cleanup^|help]
echo.
echo   run      Reset and execute the real init + app + sidecar pipeline.
echo   verify   Show container states, shared input, sidecar logs and refined records.
echo   cleanup  Delete the Lab 1.2 ConfigMap and Pod.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 1.2 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe pod %POD% -n %NS%
echo Gợi ý: kubectl logs %POD% -n %NS% -c sidecar
exit /b 1
