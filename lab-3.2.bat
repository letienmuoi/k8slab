@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "POD=pipeline-secure-auditor"
set "MANIFEST=lab-3.2-security-context.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="apply" goto :apply_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :deploy
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 3.2 hoàn tất: non-root, read-only rootfs, drop ALL và no privilege escalation.
exit /b 0

:apply_action
call :precheck
if errorlevel 1 goto :fail
call :deploy
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
echo [OK] Đã xóa Pod của Lab 3.2.
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

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
for %%D in (flink-jobmanager iceberg-rest minio) do (
  kubectl wait -n "%NS%" --for=condition=Available deployment/%%D --timeout=30s
  if errorlevel 1 exit /b 1
)
kubectl apply --dry-run=server -f "%MANIFEST%" >nul
exit /b %errorlevel%

:deploy
echo.
echo [Lab 3.2] Deploy locked-down Pod...
kubectl delete pod "%POD%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready pod/%POD% --timeout=120s
exit /b %errorlevel%

:verify
kubectl get pod "%POD%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có pod/%POD%.
  exit /b 1
)
set "RUN_AS_NON_ROOT="
set "RUN_AS_USER="
set "READ_ONLY_ROOT="
set "ALLOW_ESCALATION="
set "DROP_CAPS="
for /f "delims=" %%V in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.securityContext.runAsNonRoot}"') do set "RUN_AS_NON_ROOT=%%V"
for /f "delims=" %%V in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.securityContext.runAsUser}"') do set "RUN_AS_USER=%%V"
for /f "delims=" %%V in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].securityContext.readOnlyRootFilesystem}"') do set "READ_ONLY_ROOT=%%V"
for /f "delims=" %%V in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].securityContext.allowPrivilegeEscalation}"') do set "ALLOW_ESCALATION=%%V"
for /f "delims=" %%V in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.spec.containers[0].securityContext.capabilities.drop[0]}"') do set "DROP_CAPS=%%V"
echo run_as_non_root=%RUN_AS_NON_ROOT%
echo run_as_user=%RUN_AS_USER%
echo read_only_root_filesystem=%READ_ONLY_ROOT%
echo allow_privilege_escalation=%ALLOW_ESCALATION%
echo dropped_capabilities=%DROP_CAPS%
if not "%RUN_AS_NON_ROOT%"=="true" exit /b 1
if not "%RUN_AS_USER%"=="10001" exit /b 1
if not "%READ_ONLY_ROOT%"=="true" exit /b 1
if not "%ALLOW_ESCALATION%"=="false" exit /b 1
if not "%DROP_CAPS%"=="ALL" exit /b 1
set "RUNTIME_UID="
for /f "delims=" %%U in ('kubectl exec "%POD%" -n "%NS%" -- /usr/bin/id -u') do set "RUNTIME_UID=%%U"
echo runtime_uid=%RUNTIME_UID%
if not "%RUNTIME_UID%"=="10001" exit /b 1
kubectl exec "%POD%" -n "%NS%" -- /usr/bin/touch /rootfs-write-test >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Root filesystem ghi được ngoài dự kiến.
  exit /b 1
)
echo rootfs_write=blocked_as_expected
kubectl exec "%POD%" -n "%NS%" -- /usr/bin/touch /tmp/secure-write-test
if errorlevel 1 exit /b 1
kubectl exec "%POD%" -n "%NS%" -- /usr/bin/rm /tmp/secure-write-test
if errorlevel 1 exit /b 1
echo emptydir_write=allowed_as_expected
kubectl logs "%POD%" -n "%NS%" --tail=10
if errorlevel 1 exit /b 1
kubectl logs "%POD%" -n "%NS%" --tail=10 | findstr /C:"event=secure_dependency_audit" >nul
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|apply^|verify^|cleanup^|help]
echo.
echo   run      Deploy and verify the complete security lockdown.
echo   apply    Validate and deploy the Pod.
echo   verify   Check manifest fields, runtime UID and write behavior.
echo   cleanup  Delete the Lab 3.2 Pod.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 3.2 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe pod %POD% -n %NS%
echo Gợi ý: kubectl logs %POD% -n %NS%
exit /b 1
