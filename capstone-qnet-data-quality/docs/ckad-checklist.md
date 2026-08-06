# Mandatory CKAD checklist mapping

Every Required item maps to a repository path, cluster resource, and a command
that can be demonstrated without editing live YAML.

## Application Design and Build

| ID | Implementation | Repository evidence | Demo |
|---|---|---|---|
| D1 | Five independent images and Dockerfiles | `services/*/Dockerfile`, `scripts/build.*` | `docker image ls mualanhlung017/qnet-*` |
| D2 | APIs as Deployments; seed Job; observer CronJob | `k8s/base/*.yaml`, `k8s/jobs/seed-job.yaml`, `k8s/security/observer-cronjob.yaml` | `kubectl get deploy,job,cronjob -n qnet-capstone` |
| D3 | Gateway init + main + sidecar | `k8s/base/gateway.yaml` | `kubectl get pod ... -o jsonpath` and `logs -c` |
| D4 | Runtime and access-log `emptyDir` | `k8s/base/gateway.yaml` | init and sidecar logs |
| D5 | 1Gi catalog PVC | `k8s/storage/pvc.yaml` | `scripts/pvc-test.bat` |
| D6 | Standard labels and normalizer blue/green track | all base manifests | `scripts/blue-green.bat green` |

## Application Deployment

| ID | Implementation | Repository evidence | Demo |
|---|---|---|---|
| P1 | All five long-running contexts are Deployments, dev starts at one replica | `k8s/base/` | `kubectl get deployment -n qnet-capstone` |
| P2 | Quality 1.0.0 → 1.1.0 rollout and undo | `scripts/rollout.bat`, README §11 | `scripts/rollout.bat update` |
| P3 | Normalizer blue/green Service selector | `k8s/base/normalizer.yaml` | `scripts/blue-green.bat green` |
| P4 | Ingest HPA CPU 50%, min 1, max 4 | `k8s/base/hpa.yaml` | `kubectl describe hpa qnet-ingest -n qnet-capstone` |
| P5 | Base + dev/prod overlays change tags/replicas | `k8s/base`, `k8s/overlays/*` | `kubectl kustomize ...` |
| P6 | Quality Helm chart with values upgrade/rollback | `helm/qnet-quality` | `scripts/helm-demo.bat run` |

## Environment, Configuration and Security

| ID | Implementation | Repository evidence | Demo |
|---|---|---|---|
| C1 | Endpoint/threshold ConfigMap as env; init renders volume config | `k8s/base/configmap.yaml`, `gateway.yaml` | `kubectl get cm ... -o yaml` |
| C2 | Public and catalog tokens in runtime-created Secret | `scripts/create-secret.bat`, `secret.env.example` | `kubectl describe secret qnet-secrets` |
| C3 | UID 10001, no escalation, drop ALL, read-only root, seccomp | all workload manifests | jsonpath security contexts |
| C4 | Observer SA + Role + RoleBinding, in-cluster API call | `k8s/security` | `scripts/rbac-test.bat` |
| C5 | Namespace ResourceQuota + LimitRange | `k8s/quota` | `kubectl describe quota,limitrange` |
| C6 | Requests/limits on app, init, sidecar, Job, CronJob | all workload manifests | `scripts/verify.bat` |

## Services and Networking

| ID | Implementation | Repository evidence | Demo |
|---|---|---|---|
| N1 | Five internal ClusterIP Services | `k8s/base/*.yaml` | `kubectl get svc -n qnet-capstone` |
| N2 | North-south exposure via Ingress | `k8s/network/ingress.yaml` | call controller `/` |
| N3 | `/` → gateway, `/api/quality` → quality | `k8s/network/ingress.yaml` | `kubectl describe ingress` and two calls |
| N4 | Default-deny ingress, explicit service paths, worker/catalog egress restrictions | `k8s/network/network-policies.yaml` | `scripts/network-test.bat` |
| N5 | Named target ports and verified EndpointSlices | Service manifests | `kubectl get endpointslice -n qnet-capstone` |

## Observability and Maintenance

| ID | Implementation | Repository evidence | Demo |
|---|---|---|---|
| O1 | HTTP liveness on all Deployments | every `k8s/base/*service*.yaml` workload | jsonpath/describe Pod |
| O2 | HTTP readiness on all Deployments | every Deployment manifest | `kubectl get pods` and EndpointSlices |
| O3 | Gateway startup probe protects config bootstrap | `k8s/base/gateway.yaml` | `kubectl describe pod` |
| O4 | Logs/describe/events/top runbook | README §20, `docs/demo-runbook.md` | commands in runbook |
| O5 | Current APIs: apps/v1, batch/v1, networking.k8s.io/v1, autoscaling/v2, RBAC v1 | all manifests | client/server dry-run |

## Static acceptance audit

Useful review commands:

```cmd
kubectl kustomize .\k8s\overlays\dev | kubectl apply --dry-run=server -f -
kubectl kustomize .\k8s\overlays\prod | kubectl apply --dry-run=server -f -
helm lint .\helm\qnet-quality
scripts\verify.bat
```

## Automatic fail conditions

| Condition | Prevention |
|---|---|
| Fewer than 3 services | Exactly 5 independent services |
| Docker Compose only | No Compose dependency; Kubernetes is primary runtime |
| Plaintext Secret in Git | Secret values are empty/example and created from environment |
| No external exposure | Two-path Ingress |
| Pods not Ready | deploy script blocks on six Deployment rollouts |
