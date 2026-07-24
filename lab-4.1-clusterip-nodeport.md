# Lab 4.1: ClusterIP & NodePort với frontend/backend thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Services and Networking.

## Mục tiêu

- Tạo backend Service loại ClusterIP.
- Tạo frontend Service loại NodePort.
- Chẩn đoán Service selector không match Pod labels.
- Sửa selector và kiểm tra Endpoints/EndpointSlices.
- Gọi LineNormalizer thật qua cả frontend và backend.

## Kiến trúc

```text
NodeIP:30081
  -> Service pipeline-frontend (NodePort)
  -> Pod pipeline-frontend
  -> Service pipeline-backend (ClusterIP)
  -> 2 Pods pipeline-backend
  -> NFKC + trim + collapse whitespace + lowercase
```

Cả frontend và backend chạy bằng image `mualanhlung017/ai-data-pipeline:1.0.2`. Init containers compile hai Java entrypoint nhỏ; backend dùng đúng thuật toán `LineNormalizer` của project.

## Lỗi được cài chủ động

Backend Pods có label:

```yaml
component: normalizer-backend
```

Nhưng Service ban đầu chọn:

```yaml
component: normalizer-backend-broken
```

Vì không có Pod match đầy đủ selector, Service tồn tại nhưng không có endpoint. Frontend `/api` trả `502` trong trạng thái này.

## Phần 0 — Deploy trạng thái lỗi

```cmd
kubectl apply -f .\lab-4.1-services.yaml
kubectl rollout status deployment/pipeline-backend -n data-platform --timeout=120s
kubectl rollout status deployment/pipeline-frontend -n data-platform --timeout=120s
```

Kiểm tra Service types:

```cmd
kubectl get service pipeline-backend pipeline-frontend -n data-platform
```

Expected:

```text
pipeline-backend    ClusterIP
pipeline-frontend   NodePort ... 8080:30081/TCP
```

## Phần 1 — Diagnose selector mismatch

So sánh selector và labels:

```cmd
kubectl get service pipeline-backend -n data-platform -o jsonpath="{.spec.selector}"
kubectl get pods -n data-platform -l lab=4.1 --show-labels
kubectl get pods -n data-platform -l "app=ai-data-pipeline,lab=4.1,component=normalizer-backend-broken"
```

Lệnh cuối trả `No resources found`.

Kiểm tra Endpoints:

```cmd
kubectl get endpoints pipeline-backend -n data-platform
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-backend
kubectl describe service pipeline-backend -n data-platform
```

`ENDPOINTS` phải là `<none>` trước khi sửa.

## Phần 2 — Fix selector

Windows `cmd`:

```cmd
kubectl patch service pipeline-backend -n data-platform --type=merge -p "{\"spec\":{\"selector\":{\"app\":\"ai-data-pipeline\",\"lab\":\"4.1\",\"component\":\"normalizer-backend\"}}}"
```

Kiểm tra lại:

```cmd
kubectl get endpoints pipeline-backend -n data-platform
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-backend -o wide
```

Phải có hai backend Pod IP ở port `8080`.

## Phần 3 — Verify ClusterIP

Gọi từ một Pod có sẵn trong cluster:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://pipeline-backend:8080/api?line=%20%20DU%20%20%20LIEU%09AI%20%20"
```

Expected:

```text
component=backend
normalized=du lieu ai
character_count=10
```

## Phần 4 — Verify NodePort

Lấy Node IP và NodePort:

```cmd
kubectl get nodes -o wide
kubectl get service pipeline-frontend -n data-platform -o jsonpath="{.spec.ports[0].nodePort}"
```

Cluster local hiện dùng Node IP `172.18.0.2`; lấy giá trị thực tế từ lệnh trên thay vì hard-code.

Gọi NodePort từ trong cluster:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://172.18.0.2:30081/
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://172.18.0.2:30081/api?line=KUBERNETES%20DATA"
```

Response thứ hai phải đi qua frontend rồi tới backend:

```text
component=frontend
routed_by=frontend-service
backend_status=200
component=backend
normalized=kubernetes data
```

Với cluster chạy bên trong Docker, NodePort có thể không được publish trực tiếp ra Windows host. Kiểm tra từ Pod tới Node IP vẫn xác nhận đúng NodePort/kube-proxy path. Nếu cần gọi từ host:

```cmd
kubectl port-forward -n data-platform service/pipeline-frontend 18081:8080
```

Sau đó mở `http://localhost:18081`.

## Exam-speed commands

```cmd
kubectl expose deployment NAME --name=SERVICE --port=80 --target-port=8080 --type=ClusterIP
kubectl expose deployment NAME --name=SERVICE --port=80 --target-port=8080 --type=NodePort
kubectl get service NAME -o wide
kubectl get endpoints NAME
kubectl get endpointslice -l kubernetes.io/service-name=NAME
kubectl get pods --show-labels
```

## Batch runner

```cmd
lab-4.1.bat run
lab-4.1.bat deploy
lab-4.1.bat diagnose
lab-4.1.bat fix
lab-4.1.bat verify
lab-4.1.bat cleanup
```

## Cleanup

```cmd
kubectl delete -f .\lab-4.1-services.yaml --ignore-not-found
```

Cleanup chỉ xóa frontend/backend của lab.
