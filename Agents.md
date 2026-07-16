# Session Notes

## Environment

- Workspace: `C:\Users\franc\source\muoilt_k8slab`
- User is working on Windows, usually from `cmd`.
- Docker Desktop is installed.
- Kubernetes is enabled locally.
- `kubectl` is installed. Observed client version: `v1.36.1`.

## Lab 1.1: The 60-Second Pod

Objective:

- Create a Pod imperatively with labels, environment variables, and resource requests/limits.
- Export a manifest using `--dry-run=client -o yaml`.
- Verify Pod state quickly without opening an editor.
- Run a real 60-second operational check against the live Flink REST API.

Local files:

```text
pod-60.yaml
lab-1.1-60-second-pod.md
```

Business behavior:

- The Pod runs in namespace `data-platform` with image `mualanhlung017/ai-data-pipeline:1.0.2`.
- It queries `http://flink-jobmanager:8081/jobs/overview` every 10 seconds for about 60 seconds.
- Each log line is a real Flink job snapshot. If `curl -f` cannot reach Flink, the Pod exits with an error.
- On success, the Pod reaches `Succeeded` / `Completed` with exit code `0`.

Important CLI behavior:

- `kubectl run ... --dry-run=client -o yaml > pod-60.yaml` only writes a manifest file. It does not create the Pod.
- `--dry-run=client -o yaml` must appear before `--command --`; everything after `--` is passed to the container.
- `--override-type=strategic` merges resource settings into the generated container without replacing its image, command, or environment.
- After dry-run export, create the Pod with `kubectl create -f .\pod-60.yaml`.

Working one-line Windows `cmd` command:

```cmd
kubectl run pod-60 --namespace=data-platform --image=mualanhlung017/ai-data-pipeline:1.0.2 --image-pull-policy=IfNotPresent --restart=Never --labels=app=ai-data-pipeline,lab=1.1,component=flink-monitor --annotations=lab.muoilt.vn/purpose=monitor-flink-for-60-seconds --env=APP_ENV=lab --env=OWNER=franc --env=CHECK_TARGET=http://flink-jobmanager:8081/jobs/overview --env=CHECK_INTERVAL_SECONDS=10 --env=MONITOR_DURATION_SECONDS=60 --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"pod-60\",\"resources\":{\"requests\":{\"cpu\":\"25m\",\"memory\":\"32Mi\"},\"limits\":{\"cpu\":\"100m\",\"memory\":\"128Mi\"}}}]}}" --override-type=strategic --dry-run=client -o yaml --command -- /usr/bin/bash -ec "deadline=$((SECONDS + MONITOR_DURATION_SECONDS)); while (( SECONDS < deadline )); do /usr/bin/curl -fsS \"$CHECK_TARGET\"; printf \"\\n\"; /usr/bin/sleep \"$CHECK_INTERVAL_SECONDS\"; done" > pod-60.yaml
```

Then:

```cmd
kubectl create -f .\pod-60.yaml
kubectl get pod pod-60 -n data-platform --show-labels
```

Fast verification commands:

```cmd
kubectl get pod pod-60 -n data-platform -o jsonpath="{.metadata.labels}"
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].env}"
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].resources}"
kubectl logs pod-60 -n data-platform
kubectl describe pod pod-60 -n data-platform
```

Wait and inspect completion:

```cmd
kubectl wait -n data-platform --for=jsonpath="{.status.phase}"=Succeeded pod/pod-60 --timeout=90s
kubectl get pod pod-60 -n data-platform -o jsonpath="{.status.containerStatuses[0].state.terminated.exitCode}"
```

Cleanup:

```cmd
kubectl delete pod pod-60 -n data-platform --ignore-not-found
```

## Lab 1.2: Init + Sidecar Pattern

Objective:

- Build a multi-container Pod with one init container, one app container, and one sidecar container.
- Run real file-to-Kafka ingestion through the project image and the live `data-platform` stack.
- Share work files and application logs through `emptyDir` volumes.
- Read sidecar output with `kubectl logs -c`.

Local files:

```text
lab-1.2-init-sidecar.yaml
lab-1.2-init-sidecar.md
```

Image choice:

```text
mualanhlung017/ai-data-pipeline:1.0.2
```

The manifest contains a ConfigMap and Pod in namespace `data-platform`:

- Init container copies `input.txt` and `pipeline.sql` into the `pipeline-work` emptyDir and creates `app.log` in `pipeline-logs`.
- App container runs Flink SQL Client in bounded local mode, reads the real input file, and inserts records into Kafka `raw-data`.
- The existing Flink Deployment normalizes those records and writes `refined-data` plus Iceberg tables.
- Sidecar tails the real SQL Client log from the shared log volume.

Run:

```cmd
kubectl apply -f .\lab-1.2-init-sidecar.yaml
```

Verify:

```cmd
kubectl wait -n data-platform --for=condition=Initialized pod/pipeline-init-sidecar-demo --timeout=120s
kubectl wait -n data-platform --for=jsonpath="{.status.containerStatuses[?(@.name=='app')].state.terminated.exitCode}"=0 pod/pipeline-init-sidecar-demo --timeout=180s
kubectl get pod pipeline-init-sidecar-demo -n data-platform
kubectl logs pipeline-init-sidecar-demo -n data-platform -c sidecar
kubectl exec pipeline-init-sidecar-demo -n data-platform -c sidecar -- cat /work/input.txt
```

Expected behavior:

- The init container runs first and exits successfully.
- The app container exits `0` after `Complete execution of the SQL update statement.`
- The sidecar remains running and exposes app file logs through `kubectl logs -c sidecar`.
- Pod can show `1/2 NotReady`: app is completed while the classic sidecar is still running.
- `kubectl logs ... -c app` is expected to be empty because stdout/stderr are redirected to the shared log file.
- Kafka `refined-data` contains three normalized records with marker `LAB12`.

Cleanup:

```cmd
kubectl delete -f .\lab-1.2-init-sidecar.yaml
```
