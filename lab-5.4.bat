@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "RELEASE=pipeline-helm"
set "DEPLOY=pipeline-helm-auditor"
set "CHART=lab-5.4-chart"
set "UPGRADE_VALUES=lab-5.4-upgrade-values.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="lint" goto :lint_action
if /I "%ACTION%"=="install" goto :install_action
if /I "%ACTION%"=="upgrade" goto :upgrade_action
if /I "%ACTION%"=="rollback" goto :rollback_action
if /I "%ACTION%"=="history" goto :history_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :require_tools
if errorlevel 1 goto :fail
call :reset_release
if errorlevel 1 goto :fail
call :lint_chart
if errorlevel 1 goto :fail
call :install_release
if errorlevel 1 goto :fail
call :assert_state 1 1 1 stable 15
if errorlevel 1 goto :fail
call :upgrade_release
if errorlevel 1 goto :fail
call :assert_state 2 2 2 canary 5
if errorlevel 1 goto :fail
call :rollback_release
if errorlevel 1 goto :fail
call :assert_state 3 1 1 stable 15
if errorlevel 1 goto :fail
call :show_history
if errorlevel 1 goto :fail
call :verify_business
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 5.4 hoàn tất: install, values override, upgrade và rollback đều đã kiểm chứng.
exit /b 0

:lint_action
call :require_tools
if errorlevel 1 goto :fail
call :lint_chart
if errorlevel 1 goto :fail
exit /b 0

:install_action
call :require_tools
if errorlevel 1 goto :fail
call :reset_release
if errorlevel 1 goto :fail
call :lint_chart
if errorlevel 1 goto :fail
call :install_release
if errorlevel 1 goto :fail
call :assert_state 1 1 1 stable 15
if errorlevel 1 goto :fail
exit /b 0

:upgrade_action
call :require_release
if errorlevel 1 goto :fail
call :upgrade_release
if errorlevel 1 goto :fail
call :verify_business
if errorlevel 1 goto :fail
exit /b 0

:rollback_action
call :require_release
if errorlevel 1 goto :fail
call :rollback_release
if errorlevel 1 goto :fail
call :verify_business
if errorlevel 1 goto :fail
exit /b 0

:history_action
call :require_release
if errorlevel 1 goto :fail
call :show_history
exit /b %errorlevel%

:verify_action
call :require_release
if errorlevel 1 goto :fail
call :verify_business
exit /b %errorlevel%

:cleanup
call :require_tools
if errorlevel 1 goto :fail
call :reset_release
if errorlevel 1 goto :fail
echo [OK] Đã uninstall Helm release Lab 5.4.
exit /b 0

:require_tools
where kubectl >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy kubectl trong PATH.
  exit /b 1
)
set "HELM=helm"
where helm >nul 2>&1
if errorlevel 1 (
  set "HELM=%LOCALAPPDATA%\Programs\Helm\helm.exe"
  if not exist "!HELM!" (
    echo [ERROR] Không tìm thấy Helm. Cài bằng: winget install Helm.Helm
    exit /b 1
  )
)
"!HELM!" version --short
if errorlevel 1 exit /b 1
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

:require_release
call :require_tools
if errorlevel 1 exit /b 1
"!HELM!" status "%RELEASE%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có release %RELEASE%. Chạy "%~nx0 install" trước.
  exit /b 1
)
exit /b 0

:reset_release
"!HELM!" status "%RELEASE%" -n "%NS%" >nul 2>&1
if not errorlevel 1 (
  "!HELM!" uninstall "%RELEASE%" -n "%NS%" --wait --timeout 3m
  if errorlevel 1 exit /b 1
)
kubectl delete deployment "%DEPLOY%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete pod -n "%NS%" -l lab=5.4 --ignore-not-found --wait=true
exit /b %errorlevel%

:lint_chart
echo.
echo [Lab 5.4] Lint chart, render template và server-side dry-run...
"!HELM!" lint "%CHART%"
if errorlevel 1 exit /b 1
set "RENDERED=%TEMP%\lab-5.4-rendered-!RANDOM!.yaml"
"!HELM!" template "%RELEASE%" "%CHART%" -n "%NS%" --set-string image.tag=1.0.2 > "!RENDERED!"
if errorlevel 1 (
  del /q "!RENDERED!" >nul 2>&1
  exit /b 1
)
kubectl apply --dry-run=server -f "!RENDERED!" -o name
if errorlevel 1 (
  del /q "!RENDERED!" >nul 2>&1
  exit /b 1
)
del /q "!RENDERED!" >nul 2>&1
exit /b 0

:install_release
echo.
echo [Lab 5.4] Install revision 1 với CLI value overrides...
"!HELM!" install "%RELEASE%" "%CHART%" -n "%NS%" --set-string image.tag=1.0.2 --set replicaCount=1 --set releaseTrack=stable --wait --timeout 3m
if errorlevel 1 exit /b 1
call :verify_business
exit /b %errorlevel%

:upgrade_release
echo.
echo [Lab 5.4] Upgrade revision tiếp theo bằng values file: 2 replicas, canary, interval 5s...
"!HELM!" upgrade "%RELEASE%" "%CHART%" -n "%NS%" -f "%UPGRADE_VALUES%" --set-string image.tag=1.0.2 --wait --timeout 3m
if errorlevel 1 exit /b 1
call :verify_business
exit /b %errorlevel%

:rollback_release
echo.
echo [Lab 5.4] Rollback về revision 1...
"!HELM!" rollback "%RELEASE%" 1 -n "%NS%" --wait --timeout 3m
if errorlevel 1 exit /b 1
exit /b 0

:assert_state
set "EXPECTED_RELEASE_REVISION=%~1"
set "EXPECTED_MANIFEST_REVISION=%~2"
set "EXPECTED_REPLICAS=%~3"
set "EXPECTED_TRACK=%~4"
set "EXPECTED_INTERVAL=%~5"
set "RELEASE_REVISION_NOW="
set "MANIFEST_REVISION_NOW="
set "REPLICAS_NOW="
set "TRACK_NOW="
set "INTERVAL_NOW="
for /f "delims=" %%V in ('kubectl get secrets -n "%NS%" -l "owner=helm,name=%RELEASE%,status=deployed" -o jsonpath^="{.items[0].metadata.labels.version}"') do set "RELEASE_REVISION_NOW=%%V"
for /f "delims=" %%V in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[?(@.name=='auditor')].env[?(@.name=='HELM_MANIFEST_REVISION')].value}"') do set "MANIFEST_REVISION_NOW=%%V"
for /f "delims=" %%V in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.replicas}"') do set "REPLICAS_NOW=%%V"
for /f "delims=" %%V in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[?(@.name=='auditor')].env[?(@.name=='RELEASE_TRACK')].value}"') do set "TRACK_NOW=%%V"
for /f "delims=" %%V in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[?(@.name=='auditor')].env[?(@.name=='AUDIT_INTERVAL_SECONDS')].value}"') do set "INTERVAL_NOW=%%V"
echo release_revision=!RELEASE_REVISION_NOW!
echo manifest_revision=!MANIFEST_REVISION_NOW!
echo replicas=!REPLICAS_NOW!
echo release_track=!TRACK_NOW!
echo audit_interval_seconds=!INTERVAL_NOW!
if not "!RELEASE_REVISION_NOW!"=="!EXPECTED_RELEASE_REVISION!" exit /b 1
if not "!MANIFEST_REVISION_NOW!"=="!EXPECTED_MANIFEST_REVISION!" exit /b 1
if not "!REPLICAS_NOW!"=="!EXPECTED_REPLICAS!" exit /b 1
if not "!TRACK_NOW!"=="!EXPECTED_TRACK!" exit /b 1
if not "!INTERVAL_NOW!"=="!EXPECTED_INTERVAL!" exit /b 1
exit /b 0

:verify_business
kubectl rollout status deployment/%DEPLOY% -n "%NS%" --timeout=180s
if errorlevel 1 exit /b 1
set "READY_REPLICAS="
set "CURRENT_TRACK="
for /f "delims=" %%R in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.status.readyReplicas}"') do set "READY_REPLICAS=%%R"
for /f "delims=" %%T in ('kubectl get deployment "%DEPLOY%" -n "%NS%" -o jsonpath^="{.spec.template.spec.containers[?(@.name=='auditor')].env[?(@.name=='RELEASE_TRACK')].value}"') do set "CURRENT_TRACK=%%T"
echo ready_replicas=!READY_REPLICAS!
echo current_track=!CURRENT_TRACK!
if not defined READY_REPLICAS exit /b 1
if not defined CURRENT_TRACK exit /b 1
echo [Lab 5.4] Real dependency audit log:
kubectl logs -n "%NS%" -l "app.kubernetes.io/instance=%RELEASE%,release-track=!CURRENT_TRACK!" -c auditor --tail=12 --prefix=true
if errorlevel 1 exit /b 1
kubectl logs -n "%NS%" -l "app.kubernetes.io/instance=%RELEASE%,release-track=!CURRENT_TRACK!" -c auditor --tail=30 --prefix=true | findstr /C:"event=dependency_audit result=success" | findstr /C:"track=!CURRENT_TRACK!" >nul
if errorlevel 1 (
  echo [ERROR] Chưa thấy dependency audit thành công.
  exit /b 1
)
"!HELM!" status "%RELEASE%" -n "%NS%"
exit /b %errorlevel%

:show_history
"!HELM!" history "%RELEASE%" -n "%NS%"
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|lint^|install^|upgrade^|rollback^|history^|verify^|cleanup^|help]
echo.
echo   run       Install revision 1, upgrade revision 2 and rollback to revision 1.
echo   lint      Lint, render and server-side validate the chart.
echo   install   Fresh install with CLI value overrides.
echo   upgrade   Upgrade with lab-5.4-upgrade-values.yaml.
echo   rollback  Roll back to release revision 1.
echo   history   Show Helm release history.
echo   verify    Show release status and real dependency audit logs.
echo   cleanup   Uninstall the Lab 5.4 release.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 5.4 dừng vì một lệnh thất bại.
echo Gợi ý: helm status %RELEASE% -n %NS%
echo Gợi ý: helm history %RELEASE% -n %NS%
echo Gợi ý: kubectl get pods -n %NS% -l lab=5.4
exit /b 1
