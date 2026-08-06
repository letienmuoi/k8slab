# Live demo runbook — 5 to 10 minutes

Run from Windows `cmd` in the Capstone directory. Open a second terminal for
watch commands when available.

## Before class

```cmd
kubectl get nodes
kubectl get ingressclass
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get storageclass
scripts\verify.bat
```

## Minute 0–1: architecture and healthy state

Show the Mermaid diagram in README, then:

```cmd
kubectl get deployment,pod,service -n qnet-capstone
kubectl get endpointslice -n qnet-capstone
```

Talking point: five bounded services; normalizer has two release Deployments but
one stable Service.

## Minute 1–2: real business E2E

```cmd
scripts\smoke-test.bat
```

Point to normalized text, quality score, ingestion ID and persistent catalog
entry. This proves more than Pod readiness.

## Minute 2–3: config, secret, init, sidecar and probes

```cmd
kubectl get configmap qnet-platform-config -n qnet-capstone -o yaml
kubectl describe secret qnet-secrets -n qnet-capstone
kubectl get pod -n qnet-capstone -l app.kubernetes.io/name=gateway -o jsonpath="{.items[0].spec.initContainers[*].name}{' | '}{.items[0].spec.containers[*].name}{'\n'}"
kubectl logs -n qnet-capstone deployment/qnet-gateway -c runtime-config
kubectl logs -n qnet-capstone deployment/qnet-gateway -c access-log-sidecar --tail=5
kubectl describe pod -n qnet-capstone -l app.kubernetes.io/name=gateway
```

Do not decode or print Secret values.

## Minute 3–4: deployment strategies

Blue/green:

```cmd
scripts\blue-green.bat green
scripts\seed.bat
scripts\blue-green.bat blue
```

Show `pipeline.normalizer_version` and unchanged Pod AGE.

Rolling update can be shown instead when time is short:

```cmd
scripts\rollout.bat update
scripts\rollout.bat rollback
```

## Minute 4–5: autoscaling and Kustomize

```cmd
kubectl get hpa qnet-ingest -n qnet-capstone
kubectl top pods -n qnet-capstone
kubectl kustomize .\k8s\overlays\dev | findstr /C:"image:" /C:"replicas:"
kubectl kustomize .\k8s\overlays\prod | findstr /C:"image:" /C:"replicas:"
```

Explain that 50% of `100m` request is approximately `50m` average CPU.

## Minute 5–6: network isolation

```cmd
kubectl describe ingress qnet-platform -n qnet-capstone
kubectl get networkpolicy -n qnet-capstone
scripts\network-test.bat
```

The test exits zero only when the unauthorized direct backend call is blocked.

## Minute 6–7: persistent storage

```cmd
scripts\pvc-test.bat
```

Point to different Pod UIDs and identical row counts.

## Minute 7–8: ServiceAccount and quota

```cmd
scripts\rbac-test.bat
kubectl describe resourcequota qnet-project-quota -n qnet-capstone
kubectl describe limitrange qnet-container-limits -n qnet-capstone
```

Expected: list Pods yes; list Secrets no.

## Minute 8–9: Helm lifecycle

```cmd
scripts\helm-demo.bat run
```

Show revision 1 stable, revision 2 canary, revision 3 rollback.

## Minute 9–10: debug readiness

```cmd
kubectl logs -n qnet-capstone deployment/qnet-ingest -c ingest --tail=10
kubectl get events -n qnet-capstone --sort-by=.metadata.creationTimestamp
kubectl top pods -n qnet-capstone
```

Close by mapping evidence to [ckad-checklist.md](ckad-checklist.md).
