@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0.."

set "NS=qnet-capstone"
kubectl get namespace %NS% || exit /b 1
kubectl wait -n %NS% --for=condition=Available deployment --all --timeout=180s || exit /b 1
kubectl get deployment,pod,service,endpointslice,hpa,pvc,cronjob,ingress,networkpolicy -n %NS%
kubectl get resourcequota,limitrange -n %NS%
kubectl auth can-i list pods --as=system:serviceaccount:%NS%:qnet-observer -n %NS%
kubectl auth can-i list secrets --as=system:serviceaccount:%NS%:qnet-observer -n %NS%
kubectl get pods -n %NS% -o jsonpath="{range .items[*]}{.metadata.name}{' requests='}{.spec.containers[*].resources.requests}{' limits='}{.spec.containers[*].resources.limits}{'\n'}{end}"
echo [OK] Cluster-state verification hoàn tất.
