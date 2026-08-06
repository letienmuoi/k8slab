@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0.."

call .\scripts\seed.bat || exit /b 1
for /f "delims=" %%P in ('kubectl get pod -n qnet-capstone -l app.kubernetes.io/name^=catalog -o jsonpath^="{.items[0].metadata.name}"') do set "OLD_POD=%%P"
for /f "delims=" %%U in ('kubectl get pod "!OLD_POD!" -n qnet-capstone -o jsonpath^="{.metadata.uid}"') do set "OLD_UID=%%U"
for /f "delims=" %%C in ('kubectl exec "!OLD_POD!" -n qnet-capstone -- python -c "import sqlite3; print(sqlite3.connect('/data/catalog.db').execute('select count(*) from dataset_ingestions').fetchone()[0])"') do set "OLD_COUNT=%%C"

kubectl delete pod "!OLD_POD!" -n qnet-capstone --wait=true || exit /b 1
kubectl rollout status deployment/qnet-catalog -n qnet-capstone --timeout=180s || exit /b 1
for /f "delims=" %%P in ('kubectl get pod -n qnet-capstone -l app.kubernetes.io/name^=catalog -o jsonpath^="{.items[0].metadata.name}"') do set "NEW_POD=%%P"
for /f "delims=" %%U in ('kubectl get pod "!NEW_POD!" -n qnet-capstone -o jsonpath^="{.metadata.uid}"') do set "NEW_UID=%%U"
for /f "delims=" %%C in ('kubectl exec "!NEW_POD!" -n qnet-capstone -- python -c "import sqlite3; print(sqlite3.connect('/data/catalog.db').execute('select count(*) from dataset_ingestions').fetchone()[0])"') do set "NEW_COUNT=%%C"

echo old_uid=!OLD_UID!
echo new_uid=!NEW_UID!
echo old_record_count=!OLD_COUNT!
echo new_record_count=!NEW_COUNT!
if "!OLD_UID!"=="!NEW_UID!" exit /b 1
if not "!OLD_COUNT!"=="!NEW_COUNT!" exit /b 1
echo [OK] Pod UID đổi nhưng catalog records còn nguyên trên PVC.
