@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "TRACK=%~1"
if /I not "%TRACK%"=="blue" if /I not "%TRACK%"=="green" (
  echo Usage: %~nx0 [blue^|green]
  exit /b 1
)

kubectl patch service qnet-normalizer -n qnet-capstone --type=merge -p "{\"metadata\":{\"labels\":{\"active-track\":\"%TRACK%\"}},\"spec\":{\"selector\":{\"track\":\"%TRACK%\"}}}" || exit /b 1
kubectl get service qnet-normalizer -n qnet-capstone -o jsonpath="active_track={.metadata.labels.active-track} selector_track={.spec.selector.track}{'\n'}"
kubectl get endpointslice -n qnet-capstone -l kubernetes.io/service-name=qnet-normalizer -o wide
echo [OK] Stable Service đã chuyển sang %TRACK% mà không restart Deployment.
