@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

kubectl delete job qnet-seed-dataset -n qnet-capstone --ignore-not-found --wait=true || exit /b 1
kubectl apply -f .\k8s\jobs\seed-job.yaml || exit /b 1
kubectl wait -n qnet-capstone --for=condition=complete job/qnet-seed-dataset --timeout=180s || exit /b 1
kubectl logs job/qnet-seed-dataset -n qnet-capstone
