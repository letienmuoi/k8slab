@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "CONTROLLER_NS=ingress-nginx"
set "CONTROLLER_DEPLOY=ingress-nginx-controller"
set "CONTROLLER_SERVICE=ingress-nginx-controller"
set "INGRESS=pipeline-routing"
set "MANIFEST=lab-4.2-ingress.yaml"
set "CONTROLLER_URL=https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="controller" goto :controller_action
if /I "%ACTION%"=="apply" goto :apply_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="cleanup-controller" goto :cleanup_controller
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :require_kubectl
if errorlevel 1 goto :fail
call :ensure_app
if errorlevel 1 goto :fail
call :ensure_controller
if errorlevel 1 goto :fail
call :apply_ingress
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 4.2 hoàn tất: / tới frontend và /api tới backend qua Ingress controller.
exit /b 0

:controller_action
call :require_kubectl
if errorlevel 1 goto :fail
call :ensure_controller
if errorlevel 1 goto :fail
exit /b 0

:apply_action
call :require_kubectl
if errorlevel 1 goto :fail
call :ensure_app
if errorlevel 1 goto :fail
call :ensure_controller
if errorlevel 1 goto :fail
call :apply_ingress
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_kubectl
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã xóa Ingress Lab 4.2; app và controller được giữ lại.
exit /b 0

:cleanup_controller
call :require_cli
if errorlevel 1 goto :fail
kubectl get deployment "%CONTROLLER_DEPLOY%" -n "%CONTROLLER_NS%" >nul 2>&1
if errorlevel 1 (
  echo [OK] Ingress controller không tồn tại.
  exit /b 0
)
set "CONTROLLER_OWNER="
for /f "delims=" %%O in ('kubectl get deployment "%CONTROLLER_DEPLOY%" -n "%CONTROLLER_NS%" -o jsonpath^="{.metadata.annotations.lab\.muoilt\.vn/managed-by}"') do set "CONTROLLER_OWNER=%%O"
if not "%CONTROLLER_OWNER%"=="lab-4.2" (
  echo [ERROR] Controller không do Lab 4.2 quản lý; từ chối xóa.
  exit /b 1
)
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
kubectl delete -f "%CONTROLLER_URL%" --ignore-not-found --wait=true
if errorlevel 1 goto :fail
echo [OK] Đã gỡ ingress-nginx controller do Lab 4.2 cài.
exit /b 0

:require_cli
where kubectl >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy kubectl trong PATH.
  exit /b 1
)
exit /b 0

:require_kubectl
call :require_cli
if errorlevel 1 exit /b 1
kubectl get namespace "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Namespace %NS% chưa tồn tại.
  exit /b 1
)
exit /b 0

:ensure_app
kubectl get service pipeline-backend pipeline-frontend -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [Lab 4.2] Chưa có app; chạy Lab 4.1 trước...
  call lab-4.1.bat run
  if errorlevel 1 exit /b 1
)
set "BACKEND_SELECTOR="
for /f "delims=" %%S in ('kubectl get service pipeline-backend -n "%NS%" -o jsonpath^="{.spec.selector.component}"') do set "BACKEND_SELECTOR=%%S"
if not "%BACKEND_SELECTOR%"=="normalizer-backend" (
  call lab-4.1.bat fix
  if errorlevel 1 exit /b 1
)
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 5 http://pipeline-backend:8080/ready >nul
exit /b %errorlevel%

:ensure_controller
kubectl get deployment "%CONTROLLER_DEPLOY%" -n "%CONTROLLER_NS%" >nul 2>&1
if not errorlevel 1 (
  echo [Lab 4.2] Dùng ingress-nginx controller đang có.
  kubectl rollout status deployment/%CONTROLLER_DEPLOY% -n "%CONTROLLER_NS%" --timeout=180s
  if errorlevel 1 exit /b 1
  kubectl get ingressclass nginx >nul 2>&1
  exit /b %errorlevel%
)
echo.
echo [Lab 4.2] Cài ingress-nginx v1.15.1 đã pin cho local lab...
echo [WARN] ingress-nginx đã retired; không dùng cài đặt này cho production mới.
kubectl apply -f "%CONTROLLER_URL%"
if errorlevel 1 exit /b 1
kubectl wait -n "%CONTROLLER_NS%" --for=condition=complete job/ingress-nginx-admission-create --timeout=180s
if errorlevel 1 exit /b 1
kubectl wait -n "%CONTROLLER_NS%" --for=condition=complete job/ingress-nginx-admission-patch --timeout=180s
if errorlevel 1 exit /b 1
kubectl rollout status deployment/%CONTROLLER_DEPLOY% -n "%CONTROLLER_NS%" --timeout=180s
if errorlevel 1 exit /b 1
kubectl wait -n "%CONTROLLER_NS%" --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
if errorlevel 1 exit /b 1
kubectl annotate deployment "%CONTROLLER_DEPLOY%" -n "%CONTROLLER_NS%" lab.muoilt.vn/managed-by=lab-4.2 lab.muoilt.vn/upstream=controller-v1.15.1 --overwrite
exit /b %errorlevel%

:apply_ingress
echo.
echo [Lab 4.2] Apply path-based Ingress...
kubectl delete -f "%MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply --dry-run=server -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
exit /b %errorlevel%

:verify
kubectl get ingress "%INGRESS%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có ingress/%INGRESS%.
  exit /b 1
)
set "NODE_IP="
set "INGRESS_PORT="
for /f "tokens=1,2 delims==" %%A in ('kubectl get nodes -o jsonpath^="{range .items[0].status.addresses[*]}{.type}={.address}{'\n'}{end}"') do if "%%A"=="InternalIP" set "NODE_IP=%%B"
for /f "delims=" %%P in ('kubectl get service "%CONTROLLER_SERVICE%" -n "%CONTROLLER_NS%" -o jsonpath^="{.spec.ports[0].nodePort}"') do set "INGRESS_PORT=%%P"
echo node_ip=%NODE_IP%
echo ingress_http_node_port=%INGRESS_PORT%
for /l %%T in (1,1,60) do (
  kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 3 "http://%NODE_IP%:%INGRESS_PORT%/" >nul 2>&1
  if not errorlevel 1 goto :ingress_ready
  ping -n 2 127.0.0.1 >nul
)
echo [ERROR] Ingress controller chưa route được sau thời gian chờ.
exit /b 1

:ingress_ready
echo.
kubectl get ingress "%INGRESS%" -n "%NS%"
kubectl describe ingress "%INGRESS%" -n "%NS%"
echo.
echo [Lab 4.2] Ingress / response:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%INGRESS_PORT%/"
if errorlevel 1 exit /b 1
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%INGRESS_PORT%/" | findstr /C:"component=frontend" >nul
if errorlevel 1 exit /b 1
echo [Lab 4.2] Ingress /api response:
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%INGRESS_PORT%/api?line=%%20INGRESS%%20DATA%%20"
if errorlevel 1 exit /b 1
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%INGRESS_PORT%/api?line=%%20INGRESS%%20DATA%%20" | findstr /C:"component=backend" >nul
if errorlevel 1 exit /b 1
kubectl exec -n "%NS%" deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%INGRESS_PORT%/api?line=%%20INGRESS%%20DATA%%20" | findstr /C:"routed_by=frontend-service" >nul
if not errorlevel 1 (
  echo [ERROR] /api đi qua frontend thay vì route trực tiếp backend.
  exit /b 1
)
exit /b 0

:usage
echo Usage: %~nx0 [run^|controller^|apply^|verify^|cleanup^|cleanup-controller^|help]
echo.
echo   run                 Ensure app/controller, apply Ingress and verify both paths.
echo   controller          Install or verify the pinned local ingress controller.
echo   apply               Ensure prerequisites and apply the Ingress.
echo   verify              Verify / and /api through the controller NodePort.
echo   cleanup             Delete only the Lab 4.2 Ingress.
echo   cleanup-controller  Remove controller only when marked as Lab 4.2-managed.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 4.2 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe ingress %INGRESS% -n %NS%
echo Gợi ý: kubectl logs -n %CONTROLLER_NS% deployment/%CONTROLLER_DEPLOY% --tail=100
exit /b 1
