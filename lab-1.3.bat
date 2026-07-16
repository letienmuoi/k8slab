@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

set "NS=data-platform"
set "CONFIG=lab-1.3-pipeline-sql.yaml"
set "JOB_MANIFEST=lab-1.3-job.yaml"
set "CRON_MANIFEST=lab-1.3-cronjob.yaml"
set "JOB=ai-data-pipeline-once"
set "CRON=ai-data-pipeline-schedule"
set "ACTION=%~1"
if not defined ACTION set "ACTION=run"

if /I "%ACTION%"=="run" goto :run
if /I "%ACTION%"=="job" goto :job_action
if /I "%ACTION%"=="cronjob" goto :cronjob_action
if /I "%ACTION%"=="verify" goto :verify
if /I "%ACTION%"=="resume" goto :resume
if /I "%ACTION%"=="suspend" goto :suspend
if /I "%ACTION%"=="cleanup" goto :cleanup
if /I "%ACTION%"=="help" goto :usage
if /I "%ACTION%"=="--help" goto :usage
goto :unknown

:run
call :precheck
if errorlevel 1 goto :fail
call :cleanup_resources
if errorlevel 1 goto :fail
call :run_job
if errorlevel 1 goto :fail
call :run_cronjob
if errorlevel 1 goto :fail
call :show_results
if errorlevel 1 goto :fail
echo.
echo [OK] Lab 1.3 hoàn tất. CronJob đã tự suspend sau một lần schedule thật.
echo Dùng "%~nx0 resume" để bật lịch hoặc "%~nx0 cleanup" để xóa tài nguyên lab.
exit /b 0

:job_action
call :precheck
if errorlevel 1 goto :fail
call :run_job
if errorlevel 1 goto :fail
exit /b 0

:cronjob_action
call :precheck
if errorlevel 1 goto :fail
call :run_cronjob
if errorlevel 1 goto :fail
exit /b 0

:verify
call :require_kubectl
if errorlevel 1 goto :fail
call :show_results
exit /b %errorlevel%

:resume
call :require_kubectl
if errorlevel 1 goto :fail
kubectl patch cronjob "%CRON%" -n "%NS%" --type=merge -p "{\"spec\":{\"suspend\":false}}"
if errorlevel 1 goto :fail
kubectl get cronjob "%CRON%" -n "%NS%"
echo [WARN] CronJob đang chạy mỗi phút. Hãy dùng "%~nx0 suspend" hoặc cleanup khi thực hành xong.
exit /b 0

:suspend
call :require_kubectl
if errorlevel 1 goto :fail
kubectl patch cronjob "%CRON%" -n "%NS%" --type=merge -p "{\"spec\":{\"suspend\":true}}"
if errorlevel 1 goto :fail
kubectl get cronjob "%CRON%" -n "%NS%"
exit /b 0

:cleanup
call :require_kubectl
if errorlevel 1 goto :fail
call :cleanup_resources
if errorlevel 1 goto :fail
echo [OK] Đã xóa Job, CronJob, Job con và ConfigMap của Lab 1.3.
exit /b 0

:precheck
call :require_kubectl
if errorlevel 1 exit /b 1
echo [Lab 1.3] Kiểm tra Kafka và Flink thật...
kubectl wait -n "%NS%" --for=condition=Available deployment/kafka --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-jobmanager --timeout=30s
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=Available deployment/flink-taskmanager --timeout=30s
exit /b %errorlevel%

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

:run_job
echo.
echo [Lab 1.3] Tạo ConfigMap SQL và one-off Job...
kubectl apply -f "%CONFIG%"
if errorlevel 1 exit /b 1
kubectl delete job "%JOB%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%JOB_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl wait -n "%NS%" --for=condition=complete job/%JOB% --timeout=240s
if errorlevel 1 exit /b 1
kubectl get job "%JOB%" -n "%NS%"
echo backoffLimit:
kubectl get job "%JOB%" -n "%NS%" -o jsonpath="{.spec.backoffLimit}"
echo.
echo restartPolicy:
kubectl get job "%JOB%" -n "%NS%" -o jsonpath="{.spec.template.spec.restartPolicy}"
echo.
kubectl logs job/%JOB% -n "%NS%" --tail=80
exit /b %errorlevel%

:run_cronjob
echo.
echo [Lab 1.3] Tạo CronJob và chờ scheduler sinh một Job thật...
kubectl apply -f "%CONFIG%"
if errorlevel 1 exit /b 1
kubectl delete cronjob "%CRON%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl apply -f "%CRON_MANIFEST%"
if errorlevel 1 exit /b 1
kubectl get cronjob "%CRON%" -n "%NS%"

echo [Lab 1.3] Có thể phải chờ tới đầu phút kế tiếp...
kubectl wait -n "%NS%" --for=jsonpath="{.status.lastScheduleTime}" cronjob/%CRON% --timeout=100s
if errorlevel 1 exit /b 1

echo [Lab 1.3] Suspend để không tiếp tục tạo Job mỗi phút...
kubectl patch cronjob "%CRON%" -n "%NS%" --type=merge -p "{\"spec\":{\"suspend\":true}}"
if errorlevel 1 exit /b 1

set "SCHEDULED_JOB="
for /f "delims=" %%J in ('kubectl get jobs -n "%NS%" -l "lab=1.3,workload=scheduled" --sort-by=.metadata.creationTimestamp -o name 2^>nul') do set "SCHEDULED_JOB=%%J"
if not defined SCHEDULED_JOB (
  echo [ERROR] CronJob có lastScheduleTime nhưng chưa tìm thấy Job con.
  exit /b 1
)

echo [Lab 1.3] Chờ %SCHEDULED_JOB% hoàn thành...
kubectl wait -n "%NS%" --for=condition=complete %SCHEDULED_JOB% --timeout=240s
if errorlevel 1 exit /b 1
kubectl logs -n "%NS%" %SCHEDULED_JOB% --tail=80
exit /b %errorlevel%

:show_results
echo.
echo [Lab 1.3] Job/CronJob theo label:
kubectl get cronjob,job -n "%NS%" -l lab=1.3
if errorlevel 1 exit /b 1
echo.
echo [Lab 1.3] Record đã qua LineNormalizer trong refined-data:
kubectl exec -n "%NS%" deployment/kafka -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic refined-data --from-beginning --timeout-ms 10000 2>nul | findstr /I "LAB13 KUBERNETES CRONJOB"
if errorlevel 1 echo [WARN] Chưa thấy record LAB13; pipeline streaming có thể cần thêm vài giây.
exit /b 0

:cleanup_resources
kubectl delete cronjob "%CRON%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete job ai-data-pipeline-manual "%JOB%" -n "%NS%" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete jobs -n "%NS%" -l "lab=1.3,workload=scheduled" --ignore-not-found --wait=true
if errorlevel 1 exit /b 1
kubectl delete -f "%CONFIG%" --ignore-not-found --wait=true
exit /b %errorlevel%

:usage
echo Usage: %~nx0 [run^|job^|cronjob^|verify^|resume^|suspend^|cleanup^|help]
echo.
echo   run      Run one-off Job, wait for one real CronJob schedule, then suspend it.
echo   job      Run only the one-off Job.
echo   cronjob  Recreate CronJob, wait for one scheduled Job, then suspend it.
echo   verify   List Lab 1.3 resources and query refined-data.
echo   resume   Resume the every-minute CronJob schedule.
echo   suspend  Suspend the CronJob schedule.
echo   cleanup  Delete only Lab 1.3 Kubernetes resources.
exit /b 0

:unknown
echo [ERROR] Action không hợp lệ: %ACTION%
call :usage
exit /b 1

:fail
echo.
echo [FAILED] Lab 1.3 dừng vì một lệnh thất bại.
echo Gợi ý: kubectl get pods,job,cronjob -n %NS% -l lab=1.3
exit /b 1
