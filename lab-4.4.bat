@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "PVC=pipeline-audit-state"
set "POD=pipeline-pvc-auditor"
set "STATE_FILE=/var/lib/pipeline-state/dependency-audit.log"
set "PVC_MANIFEST=lab-4.4-pvc.yaml"
set "POD_MANIFEST=lab-4.4-pvc-pod.yaml"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="provision" goto :provision_action
if /I "%ACTION%"=="recreate" goto :recreate_action
if /I "%ACTION%"=="verify" goto :verify_action
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :reset_storage
if errorlevel 1 goto :fail
call :provision
if errorlevel 1 goto :fail
call :capture_before
if errorlevel 1 goto :fail
call :recreate
if errorlevel 1 goto :fail
call :capture_after
if errorlevel 1 goto :fail
call :compare_hashes
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 4.4 hoàn tất: PVC 1Gi giữ nguyên pipeline snapshot qua Pod recreation.
exit /b 0

:provision_action
call :precheck
if errorlevel 1 goto :fail
call :reset_storage
if errorlevel 1 goto :fail
call :provision
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:recreate_action
call :require_storage
if errorlevel 1 goto :fail
call :capture_before
if errorlevel 1 goto :fail
call :recreate
if errorlevel 1 goto :fail
call :capture_after
if errorlevel 1 goto :fail
call :compare_hashes
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:verify_action
call :require_storage
if errorlevel 1 goto :fail
call :verify
if errorlevel 1 goto :fail
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call :reset_storage
if errorlevel 1 goto :fail
echo [OK] Đã xóa Pod, PVC và dữ liệu Lab 4.4.
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
kubectl get storageclass standard >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Không tìm thấy StorageClass standard.
  exit /b 1
)
for %%D in (flink-jobmanager iceberg-rest minio) do (
  kubectl wait -n "%NS%" --for=condition=Available deployment/%%D --timeout=30s
  if errorlevel 1 exit /b 1
)
kubectl apply --dry-run=server -f "%PVC_MANIFEST%" >nul
exit /b %errorlevel%

:require_storage
call :require_kubectl
if errorlevel 1 exit /b 1
kubectl get pvc "%PVC%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có pvc/%PVC%. Chạy "%~nx0 provision" trước.
  exit /b 1
)
kubectl get pod "%POD%" -n "%NS%" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Chưa có pod/%POD%.
  exit /b 1
)
exit /b 0

:reset_storage
kubectl delete -f "%POD_MANIFEST%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete -f "%PVC_MANIFEST%" --ignore-not-found --wait=true
exit /b %errorlevel%

:provision
echo.
echo [Lab 4.4] Request PVC 1Gi bằng dynamic provisioning...
kubectl apply -f "%PVC_MANIFEST%"
if errorlevel 1 exit /b 1
echo [Lab 4.4] Tạo consumer Pod để trigger WaitForFirstConsumer...
kubectl apply --dry-run=server -f "%POD_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl apply -f "%POD_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=jsonpath="{.status.phase}"=Bound pvc/%PVC% --timeout=120s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready pod/%POD% --timeout=120s
if errorlevel 1 exit /b 1
kubectl get pvc "%PVC%" -n "%NS%" -o wide
exit /b %errorlevel%

:capture_before
set "STATE_HASH_BEFORE="
set "POD_UID_BEFORE="
for /f "tokens=1" %%H in ('kubectl exec "%POD%" -n "%NS%" -- /usr/bin/sha256sum "%STATE_FILE%"') do set "STATE_HASH_BEFORE=%%H"
for /f "delims=" %%U in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.metadata.uid}"') do set "POD_UID_BEFORE=%%U"
echo state_hash_before=%STATE_HASH_BEFORE%
echo pod_uid_before=%POD_UID_BEFORE%
if not defined STATE_HASH_BEFORE exit /b 1
if not defined POD_UID_BEFORE exit /b 1
exit /b 0

:recreate
echo.
echo [Lab 4.4] Xóa Pod nhưng giữ PVC Bound...
kubectl delete pod "%POD%" -n "%NS%" --wait=true
if errorlevel 1 exit /b 1
set "PVC_PHASE="
for /f "delims=" %%P in ('kubectl get pvc "%PVC%" -n "%NS%" -o jsonpath^="{.status.phase}"') do set "PVC_PHASE=%%P"
echo pvc_after_pod_delete=%PVC_PHASE%
if not "%PVC_PHASE%"=="Bound" exit /b 1
echo [Lab 4.4] Tạo lại Pod từ cùng manifest...
kubectl apply -f "%POD_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Ready pod/%POD% --timeout=120s
exit /b %errorlevel%

:capture_after
set "STATE_HASH_AFTER="
set "POD_UID_AFTER="
for /f "tokens=1" %%H in ('kubectl exec "%POD%" -n "%NS%" -- /usr/bin/sha256sum "%STATE_FILE%"') do set "STATE_HASH_AFTER=%%H"
for /f "delims=" %%U in ('kubectl get pod "%POD%" -n "%NS%" -o jsonpath^="{.metadata.uid}"') do set "POD_UID_AFTER=%%U"
echo state_hash_after=%STATE_HASH_AFTER%
echo pod_uid_after=%POD_UID_AFTER%
if not defined STATE_HASH_AFTER exit /b 1
if not defined POD_UID_AFTER exit /b 1
exit /b 0

:compare_hashes
if not "%STATE_HASH_BEFORE%"=="%STATE_HASH_AFTER%" (
  echo [ERROR] Snapshot checksum thay đổi sau recreate.
  exit /b 1
)
if "%POD_UID_BEFORE%"=="%POD_UID_AFTER%" (
  echo [ERROR] Pod UID không đổi; Pod chưa thực sự được recreate.
  exit /b 1
)
echo persistence_checksum=unchanged
echo pod_identity=recreated
exit /b 0

:verify
set "PVC_PHASE="
set "PVC_SIZE="
set "STORAGE_CLASS="
for /f "delims=" %%V in ('kubectl get pvc "%PVC%" -n "%NS%" -o jsonpath^="{.status.phase}"') do set "PVC_PHASE=%%V"
for /f "delims=" %%V in ('kubectl get pvc "%PVC%" -n "%NS%" -o jsonpath^="{.status.capacity.storage}"') do set "PVC_SIZE=%%V"
for /f "delims=" %%V in ('kubectl get pvc "%PVC%" -n "%NS%" -o jsonpath^="{.spec.storageClassName}"') do set "STORAGE_CLASS=%%V"
echo pvc_phase=%PVC_PHASE%
echo pvc_capacity=%PVC_SIZE%
echo storage_class=%STORAGE_CLASS%
if not "%PVC_PHASE%"=="Bound" exit /b 1
if not "%PVC_SIZE%"=="1Gi" exit /b 1
if not "%STORAGE_CLASS%"=="standard" exit /b 1
kubectl logs "%POD%" -n "%NS%"
if errorlevel 1 exit /b 1
kubectl exec "%POD%" -n "%NS%" -- /usr/bin/cat "%STATE_FILE%"
if errorlevel 1 exit /b 1
kubectl get pvc "%PVC%" -n "%NS%" -o wide
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|provision^|recreate^|verify^|cleanup^|help]
echo.
echo   run        Provision PVC, write snapshot, recreate Pod and compare hashes.
echo   provision  Reset storage, dynamically provision 1Gi and write first state.
echo   recreate   Delete/recreate Pod and require unchanged file checksum.
echo   verify     Show PVC/PV state, logs and persisted business snapshot.
echo   cleanup    Delete Pod, PVC and Lab 4.4 data.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 4.4 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl describe pvc %PVC% -n %NS%
echo Gợi ý: kubectl describe pod %POD% -n %NS%
exit /b 1
