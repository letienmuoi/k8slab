@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

echo [WARNING] Lệnh này xóa namespace qnet-capstone và PVC catalog.
set "HELM=helm"
where helm >nul 2>&1 || set "HELM=%LOCALAPPDATA%\Programs\Helm\helm.exe"
"%HELM%" uninstall qnet-quality-release -n qnet-capstone >nul 2>&1
kubectl delete namespace qnet-capstone --ignore-not-found
