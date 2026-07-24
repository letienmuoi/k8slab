# Lab 5.3 — Broken YAML Triage

Thời lượng: khoảng 45 phút
CKAD domain: Application Observability and Maintenance

## Mục tiêu

- Sửa Deployment selector không khớp Pod template labels.
- Sửa image name không hợp lệ.
- Sửa Service `targetPort` không khớp cổng ứng dụng.
- Phân biệt lỗi admission, lỗi kubelet/runtime và lỗi network runtime.

## Workload nghiệp vụ

`TriageApi` chạy bằng image
`mualanhlung017/ai-data-pipeline:1.0.2`. Endpoint `/api` gọi Flink
`/jobs/overview` thật rồi trả job state. Vì vậy request thành công cuối bài
chứng minh cả Pod, Service và dependency path đều hoạt động.

Các file checkpoint:

```text
lab-5.3-app-source.yaml
lab-5.3-broken.yaml
lab-5.3-selector-fixed.yaml
lab-5.3-fixed.yaml
```

## Lỗi 1 — Deployment selector mismatch

Trong file broken:

```yaml
selector:
  matchLabels:
    component: triage-api-selector-wrong
template:
  metadata:
    labels:
      component: triage-api
```

Kiểm tra:

```cmd
kubectl apply --dry-run=server -f .\lab-5.3-broken.yaml
```

API server từ chối với `selector does not match template labels`. Đây là lỗi
admission: Deployment và Pod chưa được tạo. Sửa selector thành
`component: triage-api`.

## Lỗi 2 — Invalid image name

Apply checkpoint sau khi sửa selector:

```cmd
kubectl apply -f .\lab-5.3-app-source.yaml
kubectl apply -f .\lab-5.3-selector-fixed.yaml
kubectl get pods -n data-platform -l lab=5.3
kubectl describe pods -n data-platform -l lab=5.3
```

Image reference `mualanhlung017/ai-data-pipeline:INVALID@@TAG` chứa hai ký tự
`@` sai cú pháp nên container runtime báo `InvalidImageName`. Sửa:

```cmd
kubectl set image deployment/pipeline-triage -n data-platform gateway=mualanhlung017/ai-data-pipeline:1.0.2
kubectl rollout status deployment/pipeline-triage -n data-platform --timeout=180s
```

## Lỗi 3 — Service targetPort mismatch

Pod đã `Ready`, EndpointSlice có Pod IP nhưng port là `9099`:

```cmd
kubectl get service pipeline-triage -n data-platform -o yaml
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-triage -o wide
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- curl -fsS --max-time 4 http://pipeline-triage:8080/api
```

Container thực tế nghe `8080`, nên sửa:

```cmd
kubectl patch service pipeline-triage -n data-platform --type=merge -p "{\"spec\":{\"ports\":[{\"name\":\"http\",\"port\":8080,\"protocol\":\"TCP\",\"targetPort\":8080}]}}"
```

Verify:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- curl -fsS http://pipeline-triage:8080/api
```

Response phải chứa `component=pipeline-triage-api` và `flink_jobs=...`.

## Exam-speed triage order

```cmd
kubectl apply --dry-run=server -f broken.yaml
kubectl get pods
kubectl describe pod POD
kubectl get service,endpointslice
kubectl logs POD -c CONTAINER
```

Thứ tự chẩn đoán:

1. API có nhận YAML không?
2. Scheduler/kubelet có tạo container không?
3. Pod có Ready không?
4. Service selector có endpoint không?
5. Endpoint port có đúng cổng app không?

## Batch runner

```cmd
lab-5.3.bat run
lab-5.3.bat selector
lab-5.3.bat runtime
lab-5.3.bat fix-image
lab-5.3.bat fix-port
lab-5.3.bat solution
lab-5.3.bat verify
lab-5.3.bat cleanup
```

`run` không bỏ qua lỗi: nó yêu cầu API rejection, `InvalidImageName`, request
failure do port 9099 và response Flink thành công sau port 8080.

## Cleanup

```cmd
lab-5.3.bat cleanup
```
