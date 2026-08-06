@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "CAN_LIST_PODS="
set "CAN_LIST_SECRETS="
for /f "delims=" %%A in ('kubectl auth can-i list pods --as=system:serviceaccount:qnet-capstone:qnet-observer -n qnet-capstone') do set "CAN_LIST_PODS=%%A"
for /f "delims=" %%A in ('kubectl auth can-i list secrets --as=system:serviceaccount:qnet-capstone:qnet-observer -n qnet-capstone') do set "CAN_LIST_SECRETS=%%A"
echo can_list_pods=%CAN_LIST_PODS%
echo can_list_secrets=%CAN_LIST_SECRETS%
if not "%CAN_LIST_PODS%"=="yes" exit /b 1
if not "%CAN_LIST_SECRETS%"=="no" exit /b 1
kubectl delete job qnet-audit-manual -n qnet-capstone --ignore-not-found --wait=true || exit /b 1
kubectl create job qnet-audit-manual -n qnet-capstone --from=cronjob/qnet-cluster-audit || exit /b 1
kubectl wait -n qnet-capstone --for=condition=complete job/qnet-audit-manual --timeout=120s || exit /b 1
kubectl logs job/qnet-audit-manual -n qnet-capstone
echo [OK] SA list Pods được, list Secrets bị từ chối và in-cluster API call thành công.
