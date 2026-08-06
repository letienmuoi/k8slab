@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "ACTION=%~1"
if not defined ACTION set "ACTION=update"

if /I "%ACTION%"=="update" (
  kubectl set image deployment/qnet-quality -n qnet-capstone quality=mualanhlung017/qnet-quality:1.1.0 || exit /b 1
  kubectl annotate deployment qnet-quality -n qnet-capstone kubernetes.io/change-cause="Upgrade quality 1.0.0 to 1.1.0" --overwrite || exit /b 1
) else if /I "%ACTION%"=="rollback" (
  kubectl rollout undo deployment/qnet-quality -n qnet-capstone || exit /b 1
) else if /I not "%ACTION%"=="status" (
  echo Usage: %~nx0 [update^|rollback^|status]
  exit /b 1
)

kubectl rollout status deployment/qnet-quality -n qnet-capstone --timeout=180s || exit /b 1
kubectl rollout history deployment/qnet-quality -n qnet-capstone
kubectl get deployment qnet-quality -n qnet-capstone -o jsonpath="image={.spec.template.spec.containers[0].image}{'\n'}"
