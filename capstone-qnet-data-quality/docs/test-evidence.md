# Local validation evidence

Validated on 2026-08-06 with Docker Desktop Kubernetes v1.36.1.

## Build and unit tests

- Built ten custom images: five services at `1.0.0` and `1.1.0`.
- Base image resolved to
  `python:3.13.5-alpine3.22@sha256:37b14db89f587f9eaa890e4a442a3fe55db452b69cca1403cc730bd0fbdc8aaf`.
- Three algorithm tests passed: NFKC/case/whitespace, v1.1 zero-width removal,
  and real quality metrics.

## Kubernetes dev overlay

- Six Deployment instances Available: five contexts plus second normalizer
  release.
- Gateway showed `2/2` containers Ready after init completion.
- Five ClusterIP Services had EndpointSlice addresses.
- PVC `qnet-catalog-data` bound dynamically at 1Gi/RWO.

## Business E2E

Smoke Job returned:

```json
{
  "event": "smoke_test_passed",
  "quality_score": 71.67
}
```

The request traversed gateway, ingest, normalizer, quality, and catalog.

## Blue/green

- Service selector changed from `track=blue` to `track=green`.
- EndpointSlice moved to the green Pod without restarting either Deployment.
- The next seed response reported `normalizer_version=1.1.0`.

## NetworkPolicy

Unauthorized Job called the normalizer Service directly and timed out:

```json
{"event":"network_policy_verified","blocked":true}
```

The allowed smoke path continued to pass.

## PVC

Catalog Pod UID changed after deletion while row count remained `3 -> 3`.

## RBAC and CronJob

```text
list pods    yes
list secrets no
```

A manual Job created from `qnet-cluster-audit` used the mounted SA token and
received HTTP 200 from the namespaced Pods API.

## HPA and Metrics

Metrics API became Available. HPA showed CPU `1%/50%`, min 1, max 4, with
conditions `AbleToScale=True` and `ScalingActive=True`.

## Ingress

Controller calls returned:

- `/` -> gateway application document;
- `/api/quality` -> quality service document.

Ingress status received the local node address after controller reconciliation.

## Kustomize prod overlay

Prod applied and passed E2E with:

| Deployment | Replicas | Image |
|---|---:|---|
| gateway | 2 | `qnet-gateway:1.1.0` |
| ingest | 2 | `qnet-ingest:1.1.0` |
| quality | 2 | `qnet-quality:1.1.0` |
| catalog | 1 | `qnet-catalog:1.1.0` |

## Helm

Chart lint passed. Live lifecycle:

```text
revision 1: install, stable, 1 replica
revision 2: upgrade, canary, 2 replicas
revision 3: rollback to revision 1 content
```
