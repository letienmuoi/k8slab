@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

where docker >nul 2>&1 || exit /b 1
where kubectl >nul 2>&1 || exit /b 1
set "HELM=helm"
where helm >nul 2>&1 || set "HELM=%LOCALAPPDATA%\Programs\Helm\helm.exe"

echo [TEST] Business algorithms
docker run --rm -v "%CD%:/workspace" -w /workspace python:3.13.5-alpine3.22 python -m unittest discover -s tests -v || exit /b 1

echo [TEST] Kustomize dev
kubectl kustomize .\k8s\overlays\dev | kubectl apply --dry-run=client -f - >nul || exit /b 1
echo [TEST] Kustomize prod
kubectl kustomize .\k8s\overlays\prod | kubectl apply --dry-run=client -f - >nul || exit /b 1

echo [TEST] Raw Job manifests
kubectl apply --dry-run=client -f .\k8s\jobs\seed-job.yaml >nul || exit /b 1
kubectl apply --dry-run=client -f .\k8s\tests\smoke-job.yaml >nul || exit /b 1
kubectl apply --dry-run=client -f .\k8s\tests\network-deny-job.yaml >nul || exit /b 1

echo [TEST] Helm chart
"%HELM%" lint .\helm\qnet-quality || exit /b 1
"%HELM%" template qnet-capstone .\helm\qnet-quality -n qnet-capstone | kubectl apply --dry-run=client -f - >nul || exit /b 1

echo [OK] Source, manifests, overlays và Helm chart đều hợp lệ.
