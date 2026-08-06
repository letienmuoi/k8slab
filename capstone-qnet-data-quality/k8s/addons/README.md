# Cluster add-on prerequisites

The application does not install cluster-scoped add-ons because cluster setup
is outside the CKAD application scope.

Before deploying, an administrator must provide:

- an Ingress controller whose IngressClass is `nginx`;
- Metrics Server exposing `v1beta1.metrics.k8s.io`;
- a policy-capable CNI;
- a default StorageClass.

Verify without changing the cluster:

```cmd
kubectl get ingressclass
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl get storageclass
kubectl get pods -n kube-system
```

Local Docker Desktop training may reuse the pinned add-on manifests/runners in
the parent lab repository. Do not treat a local `--kubelet-insecure-tls`
Metrics Server or retired training Ingress controller as a production design.
