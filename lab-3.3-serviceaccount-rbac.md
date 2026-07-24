# Lab 3.3: ServiceAccount & RBAC với Kubernetes API thật

Thời lượng gợi ý: khoảng 60 phút. CKAD domain: Application Environment, Configuration & Security.

## Mục tiêu

- Tạo ServiceAccount, Role và RoleBinding trong một namespace.
- Cấp đúng quyền `get/list/watch` cho resource Pods.
- Cho Pod dùng ServiceAccount token để gọi Kubernetes API.
- Chứng minh ServiceAccount đọc được Pods nhưng không đọc được Secrets.

## Luồng quyền

```text
Pod pipeline-rbac-observer
  -> ServiceAccount pipeline-observer
  -> RoleBinding pipeline-observer-reads-pods
  -> Role pipeline-pod-reader
  -> get/list/watch core API resource pods trong data-platform
```

Role là namespace-scoped. Không cần ClusterRole vì workload chỉ quan sát Pods trong `data-platform`.

## Nghiệp vụ

Pod chạy image project `1.0.2`. Nó đọc projected token và CA certificate tại:

```text
/var/run/secrets/kubernetes.io/serviceaccount/token
/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
/var/run/secrets/kubernetes.io/serviceaccount/namespace
```

Sau đó Pod gọi:

```text
GET /api/v1/namespaces/data-platform/pods?pretty=false&labelSelector=app%3Dai-data-pipeline
```

Token không được in ra log. Log chỉ chứa HTTP status, số Pod, response size và tên các Pod pipeline.

## Phần 0 — Validate

```cmd
kubectl apply --dry-run=client -f .\lab-3.3-serviceaccount-rbac.yaml
kubectl apply --dry-run=client -f .\lab-3.3-observer-pod.yaml
kubectl apply --dry-run=server -f .\lab-3.3-serviceaccount-rbac.yaml
```

Server-side dry-run Pod cần ServiceAccount đã tồn tại. Vì vậy apply RBAC trước, rồi validate Pod với API server:

```cmd
kubectl apply -f .\lab-3.3-serviceaccount-rbac.yaml
kubectl apply --dry-run=server -f .\lab-3.3-observer-pod.yaml
```

## Phần 1 — Apply Pod

```cmd
kubectl apply -f .\lab-3.3-observer-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-rbac-observer --timeout=120s
```

Kiểm tra object:

```cmd
kubectl get serviceaccount pipeline-observer -n data-platform
kubectl get role pipeline-pod-reader -n data-platform
kubectl get rolebinding pipeline-observer-reads-pods -n data-platform
kubectl get pod pipeline-rbac-observer -n data-platform
```

## Phần 2 — Verify quyền trước khi vào Pod

Được list Pods:

```cmd
kubectl auth can-i list pods --as=system:serviceaccount:data-platform:pipeline-observer -n data-platform
```

Expected:

```text
yes
```

Không được list Secrets:

```cmd
kubectl auth can-i list secrets --as=system:serviceaccount:data-platform:pipeline-observer -n data-platform
```

Expected:

```text
no
```

Xem toàn bộ quyền đã resolve:

```cmd
kubectl auth can-i --list --as=system:serviceaccount:data-platform:pipeline-observer -n data-platform
```

## Phần 3 — Verify Pod dùng đúng ServiceAccount

```cmd
kubectl get pod pipeline-rbac-observer -n data-platform -o jsonpath="{.spec.serviceAccountName}"
kubectl exec pipeline-rbac-observer -n data-platform -- ls -l /var/run/secrets/kubernetes.io/serviceaccount
```

Expected ServiceAccount:

```text
pipeline-observer
```

Xem API result:

```cmd
kubectl logs pipeline-rbac-observer -n data-platform --tail=10
```

Expected:

```text
event=rbac_api_list namespace=data-platform http=200
pod_names=...
```

Đây là request phát ra từ bên trong Pod bằng token của ServiceAccount, không phải `kubectl get pods` từ máy host.

## Least privilege

Role không cấp:

- quyền với `secrets`;
- động từ `create`, `update`, `patch`, `delete`;
- quyền ngoài namespace;
- wildcard `*`.

Nếu đổi endpoint trong Pod sang `/api/v1/namespaces/data-platform/secrets`, API server phải trả `403 Forbidden`.

## Lệnh CKAD cần nhớ

```cmd
kubectl create serviceaccount NAME
kubectl create role NAME --verb=get,list,watch --resource=pods
kubectl create rolebinding NAME --role=ROLE --serviceaccount=NAMESPACE:SERVICEACCOUNT
kubectl auth can-i VERB RESOURCE --as=system:serviceaccount:NAMESPACE:SERVICEACCOUNT -n NAMESPACE
```

Imperative equivalent:

```cmd
kubectl create serviceaccount pipeline-observer -n data-platform
kubectl create role pipeline-pod-reader -n data-platform --verb=get,list,watch --resource=pods
kubectl create rolebinding pipeline-observer-reads-pods -n data-platform --role=pipeline-pod-reader --serviceaccount=data-platform:pipeline-observer
```

## Batch runner

```cmd
lab-3.3.bat run
lab-3.3.bat apply
lab-3.3.bat verify
lab-3.3.bat cleanup
```

## Cleanup

```cmd
kubectl delete -f .\lab-3.3-observer-pod.yaml --ignore-not-found
kubectl delete -f .\lab-3.3-serviceaccount-rbac.yaml --ignore-not-found
```

Cleanup chỉ xóa ServiceAccount, Role, RoleBinding và Pod của Lab 3.3.
