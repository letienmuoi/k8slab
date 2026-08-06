# Project proposal

## Business domain

AI data preparation and dataset quality governance.

## User story

As a data engineer, I submit messy text records and receive deterministic
normalized data plus a quality decision, while an auditable metadata record is
stored durably.

## Five microservices

1. Gateway — authentication and external API.
2. Ingest — pipeline orchestration.
3. Normalizer — Unicode/text normalization.
4. Quality — completeness and uniqueness scoring.
5. Catalog — durable dataset metadata.

## Technical stack

- Python 3.13 standard library HTTP services.
- Five custom non-root Alpine container images.
- Kubernetes Deployments, Job, CronJob, HPA, Services, Ingress,
  NetworkPolicy, PVC, ConfigMap, Secret, RBAC, quotas, Kustomize.
- Helm chart for the quality bounded context.
- SQLite for the catalog demo volume.

## Repository

`https://github.com/letienmuoi/k8slab/tree/master/capstone-qnet-data-quality`
