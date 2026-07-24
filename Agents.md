# Session Notes

## Environment

- Workspace: `C:\Users\franc\source\muoilt_k8slab`
- User is working on Windows, usually from `cmd`.
- Docker Desktop is installed.
- Kubernetes is enabled locally.
- `kubectl` is installed. Observed client version: `v1.36.1`.

## Windows Batch Runners

The repository contains tested Windows `cmd` runners:

```text
lab-1.1.bat
lab-1.2.bat
lab-1.3.bat
lab-1.4.bat
README-batch-labs.md
```

Each script defaults to `run` and also exposes focused actions such as `verify` and `cleanup`. Run `<script> help` for the complete action list.

- Lab 1.1 exports ignored file `pod-60.generated.yaml`, runs the monitor for 60 seconds, and verifies completion.
- Lab 1.2 waits for init/app completion while leaving the classic sidecar running until cleanup.
- Lab 1.3 waits for one real CronJob schedule and then automatically sets `suspend=true`.
- Lab 1.4 executes selectors, the intentional missing-`--overwrite` failure, updates, annotations, and final count assertions.
- `.gitattributes` enforces CRLF for `.bat`; bare LF caused `cmd.exe` to misread the first characters of lines during testing.

## Lab 2.1: Rolling Update & Rollback

Objective:

- Roll a three-replica Deployment from project image `1.0.1` to `1.0.2`.
- Monitor Deployment, Pods, ReplicaSets, rollout status and rollout history.
- Simulate a bad deployment with a missing image tag and roll back to healthy v2.

Local files:

```text
lab-2.1-rolling-update.yaml
lab-2.1-rolling-update.md
lab-2.1.bat
```

Business behavior:

- `pipeline-release-auditor` is isolated from the production Flink Deployments.
- Each replica uses the real project image and audits Flink jobs, Iceberg medallion tables and MinIO readiness every 15 seconds.
- The readiness probe calls the same real endpoints and verifies the project JAR exists.
- Image `1.0.1` and `1.0.2` contain different `ai-data-pipeline.jar` SHA-256 values.
- RollingUpdate uses `maxUnavailable: 0` and `maxSurge: 1`.
- The simulated bad tag is `mualanhlung017/ai-data-pipeline:ckad-bad-does-not-exist`; three v2 Pods remain available while the surge Pod enters `ImagePullBackOff`.
- `kubectl rollout undo` returns the Deployment to `1.0.2`, the revision immediately before the bad release.

Run:

```cmd
lab-2.1.bat run
```

Cleanup:

```cmd
lab-2.1.bat cleanup
```

## Lab 2.2: Blue/Green Switch

Objective:

- Run blue (`1.0.1`) and green (`1.0.2`) Deployments simultaneously.
- Route traffic through one stable ClusterIP Service.
- Flip only `spec.selector.track` between blue and green.
- Verify EndpointSlices and the live response before and after each switch.

Local files:

```text
lab-2.2-blue-green.yaml
lab-2.2-blue-green.md
lab-2.2.bat
```

Business behavior:

- A ConfigMap contains `ReleaseGateway.java`; an `eclipse-temurin:17-jdk-jammy` init container compiles it into an `emptyDir`, then the project-image main container runs the class with its bundled Java runtime.
- Each gateway response includes its release color/version, Pod name, pipeline JAR SHA-256, real Flink jobs, real Iceberg Medallion tables and MinIO readiness.
- Blue has two Pods using image `1.0.1`; green has two Pods using image `1.0.2`.
- The single Service `pipeline-release-gateway` starts with `track: blue`.
- Patching only the Service selector moves stable DNS traffic to green without restarting either Deployment.
- Switching back to blue is the rollback path; `kubectl rollout undo` is not needed because both releases remain deployed.

Run:

```cmd
lab-2.2.bat run
```

Cleanup:

```cmd
lab-2.2.bat cleanup
```

## Lab 2.3: Scale & HPA

Objective:

- Manually scale `pipeline-normalizer-api` from two to ten replicas.
- Configure an `autoscaling/v2` HPA with min 2, max 10 and average CPU utilization target 50%.
- Exercise CPU metrics with real LineNormalizer work.

Local files:

```text
lab-2.3-metrics-server.yaml
lab-2.3-normalizer.yaml
lab-2.3-hpa.yaml
lab-2.3-load-job.yaml
lab-2.3-scale-hpa.md
lab-2.3.bat
```

Business behavior:

- `NormalizerApi.java` implements the same NFKC, trim, whitespace collapse and lowercase logic as the project `LineNormalizer`.
- An init JDK compiles it into `emptyDir`; the main container uses project image `1.0.2`.
- The `/work` endpoint performs real normalization repeatedly; the load Job calls it with eight concurrent workers.
- The main container requests `100m` CPU, so a 50% HPA target means an average of approximately `50m` CPU per Pod.
- The local cluster initially had no `metrics.k8s.io` API. The pinned Metrics Server v0.9.0 manifest adds `--kubelet-insecure-tls` for this local Docker Desktop lab.
- `cleanup` removes the Lab 2.3 workload but keeps Metrics Server. `cleanup-metrics` deletes it only if its Deployment is annotated as managed by Lab 2.3.

Run:

```cmd
lab-2.3.bat run
```

## Lab 2.4: Kustomize Overlay

Objective:

- Keep one reusable Deployment in `lab-2.4/base`.
- Build dev and prod from small Kustomize overlays without copying the Deployment.
- Transform image tag and replica count with `images` and `replicas`.

Directory layout:

```text
lab-2.4/base
lab-2.4/overlays/dev
lab-2.4/overlays/prod
```

Business behavior:

- `pipeline-kustomize-auditor` runs the real project image and verifies the pipeline JAR.
- Each Pod queries real Flink jobs, Iceberg Medallion tables and MinIO readiness.
- Dev renders `mualanhlung017/ai-data-pipeline:1.0.1` with one replica.
- Prod renders `mualanhlung017/ai-data-pipeline:1.0.2` with three replicas.
- `nameSuffix` lets both overlays run side by side on the local cluster.

Run:

```cmd
lab-2.4.bat run
```

Cleanup:

```cmd
lab-2.4.bat cleanup
```

## Lab 3.1: ConfigMap & Secret Injection

- `pipeline-catalog-secret` is created imperatively from `lab-3.1-files/catalog-client.token.example`.
- `pipeline-endpoints` is created from three literals for Flink, Iceberg and MinIO.
- Pod `pipeline-config-auditor` injects the Secret as `CATALOG_CLIENT_TOKEN` and mounts the ConfigMap at `/etc/pipeline/endpoints`.
- The token is never printed; logs contain only its SHA-256 fingerprint and real dependency responses.

Run and cleanup:

```cmd
lab-3.1.bat run
lab-3.1.bat cleanup
```

## Lab 3.2: Security Context Lockdown

- Pod `pipeline-secure-auditor` runs as UID/GID `10001` with `runAsNonRoot: true`.
- The container uses a read-only root filesystem, drops `ALL`, and disables privilege escalation.
- ServiceAccount token automount is disabled; a size-limited `emptyDir` provides writable `/tmp`.
- Runtime verification requires rootfs writes to fail and `/tmp` writes to succeed.

Run and cleanup:

```cmd
lab-3.2.bat run
lab-3.2.bat cleanup
```

## Lab 3.3: ServiceAccount & RBAC

- RBAC and Pod are split into two manifests because server-side dry-run does not persist a dry-run ServiceAccount for a later Pod document.
- ServiceAccount `pipeline-observer` receives only `get/list/watch` on core `pods` in `data-platform`.
- Pod `pipeline-rbac-observer` uses the projected token and CA to call the namespaced Pods API.
- Expected authorization: `list pods=yes`, `list secrets=no`.

Run and cleanup:

```cmd
lab-3.3.bat run
lab-3.3.bat cleanup
```

## Lab 3.4: Namespace Quotas

- All quota resources live in isolated namespace `pipeline-quota-lab`; never place the training quota on `data-platform`.
- LimitRange defaults requests to `100m/64Mi` and limits to `200m/128Mi`.
- ResourceQuota allows only `150m` total CPU requests and `300m` total CPU limits.
- The first business auditor Pod is admitted; the second is rejected because defaults would exceed both CPU quotas.

Run and cleanup:

```cmd
lab-3.4.bat run
lab-3.4.bat cleanup
```

Cleanup:

```cmd
lab-2.3.bat cleanup
lab-2.3.bat cleanup-metrics
```

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
