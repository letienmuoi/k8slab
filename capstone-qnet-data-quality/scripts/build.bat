@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "TARGET=%~1"
if not defined TARGET set "TARGET=all"
set "ACTION=%~2"

where docker >nul 2>&1 || (
  echo [ERROR] docker không có trong PATH.
  exit /b 1
)
docker info >nul 2>&1 || (
  echo [ERROR] Docker engine chưa sẵn sàng.
  exit /b 1
)

if /I "%TARGET%"=="all" (
  call :build_version 1.0.0 || exit /b 1
  call :build_version 1.1.0 || exit /b 1
) else (
  call :build_version "%TARGET%" || exit /b 1
)

echo [OK] Custom images đã được build.
exit /b 0

:build_version
set "VERSION=%~1"
for %%S in (gateway ingest normalizer quality catalog) do (
  echo [BUILD] mualanhlung017/qnet-%%S:%VERSION%
  docker build --build-arg APP_VERSION=%VERSION% -t mualanhlung017/qnet-%%S:%VERSION% "services\%%S"
  if errorlevel 1 exit /b 1
  if /I "%ACTION%"=="push" (
    docker push mualanhlung017/qnet-%%S:%VERSION%
    if errorlevel 1 exit /b 1
  )
)
exit /b 0
