@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "HELM=helm"
where helm >nul 2>&1 || set "HELM=%LOCALAPPDATA%\Programs\Helm\helm.exe"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="lint" goto :lint
if /I "%ACTION%"=="install" goto :install
if /I "%ACTION%"=="upgrade" goto :upgrade
if /I "%ACTION%"=="rollback" goto :rollback
if /I "%ACTION%"=="history" goto :history
if /I "%ACTION%"=="cleanup" goto :cleanup
echo Usage: %~nx0 [run^|lint^|install^|upgrade^|rollback^|history^|cleanup]
exit /b 1

:run
call :lint || exit /b 1
call :cleanup >nul 2>&1
call :install || exit /b 1
call :upgrade || exit /b 1
call :rollback || exit /b 1
call :history
exit /b %errorlevel%

:lint
"%HELM%" lint .\helm\qnet-quality || exit /b 1
"%HELM%" template qnet-capstone .\helm\qnet-quality -n qnet-capstone >nul
exit /b %errorlevel%

:install
"%HELM%" install qnet-quality-release .\helm\qnet-quality -n qnet-capstone --set-string image.tag=1.0.0 --set replicaCount=1 --set releaseTrack=stable --wait --timeout 3m
exit /b %errorlevel%

:upgrade
"%HELM%" upgrade qnet-quality-release .\helm\qnet-quality -n qnet-capstone -f .\helm\qnet-quality\upgrade-values.yaml --wait --timeout 3m
exit /b %errorlevel%

:rollback
"%HELM%" rollback qnet-quality-release 1 -n qnet-capstone --wait --timeout 3m
exit /b %errorlevel%

:history
"%HELM%" history qnet-quality-release -n qnet-capstone
kubectl get deployment -n qnet-capstone -l app.kubernetes.io/instance=qnet-quality-release -L release-track
exit /b %errorlevel%

:cleanup
"%HELM%" uninstall qnet-quality-release -n qnet-capstone
exit /b %errorlevel%
