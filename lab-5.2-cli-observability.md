# Lab 5.2 — CLI Observability

Thời lượng: khoảng 45 phút
CKAD domain: Application Observability and Maintenance

## Mục tiêu

- Dùng `kubectl logs -c` để chọn container.
- Dùng `kubectl logs --previous` để đọc instance trước khi restart.
- Đọc Events từ `kubectl describe` và `kubectl get events`.
- Dùng `kubectl top` để xem CPU/memory thực tế.

## Workload được quan sát

Lab này tái sử dụng Deployment `pipeline-self-healing` của Lab 5.1. Đây là
workload phù hợp hơn một Pod tạo log giả vì nó có:

- `health-api` kiểm tra Flink, Iceberg, MinIO và project JAR thật.
- `readiness-reporter` quan sát readiness và gọi `/business`.
- Một liveness failure có kiểm soát tạo ra container instance cũ, Events
  `Unhealthy`/`Killing` và restart count thật.

## Chuẩn bị

```cmd
lab-5.2.bat prepare
lab-5.2.bat restart
```

Nếu cluster chưa có Metrics API, runner cài manifest Metrics Server dành cho
local Docker Desktop/kind. Nếu cluster đã có Metrics Server do nơi khác quản
lý, runner không ghi đè.

Lấy tên Pod:

```cmd
for /f %P in ('kubectl get pods -n data-platform -l lab=5.1 -o jsonpath="{.items[0].metadata.name}"') do set POD=%P
```

## Logs theo container

```cmd
kubectl logs %POD% -n data-platform -c health-api --tail=20
kubectl logs %POD% -n data-platform -c readiness-reporter --tail=20
kubectl logs %POD% -n data-platform -c health-api --previous
```

`--previous` đọc log của instance `health-api` ngay trước restart trong cùng
Pod. Nó không có nghĩa là log của Pod cũ thuộc ReplicaSet khác.

## Describe và Events

```cmd
kubectl describe pod %POD% -n data-platform
kubectl get events -n data-platform --field-selector involvedObject.name=%POD% --sort-by=.metadata.creationTimestamp
```

Trong phần Events cần tìm:

- `Unhealthy`: HTTP liveness trả 503.
- `Killing`: kubelet restart `health-api`.
- `Started`: instance mới được chạy.

Exam-speed filter:

```cmd
kubectl get events -n data-platform --field-selector type=Warning --sort-by=.metadata.creationTimestamp
```

## Resource usage

```cmd
kubectl top pod %POD% -n data-platform --containers
kubectl top pods -n data-platform
kubectl top node
```

`kubectl top` cần Metrics API và thường phải chờ một chu kỳ sample sau khi Pod
vừa được tạo.

## Batch runner

```cmd
lab-5.2.bat run
lab-5.2.bat prepare
lab-5.2.bat restart
lab-5.2.bat logs
lab-5.2.bat events
lab-5.2.bat top
lab-5.2.bat verify
lab-5.2.bat cleanup
lab-5.2.bat cleanup-metrics
```

`run` yêu cầu cả bốn nguồn quan sát tồn tại: current logs, previous logs,
Events self-healing và Metrics API.

## Cleanup

```cmd
lab-5.2.bat cleanup
lab-5.2.bat cleanup-metrics
```

`cleanup-metrics` chỉ xóa Metrics Server nếu Deployment có annotation
`lab.muoilt.vn/managed-by=lab-5.2`.
