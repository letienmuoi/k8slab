# Lab 5.1 — Self-Healing App

Thời lượng: khoảng 45 phút
CKAD domain: Application Observability and Maintenance

## Mục tiêu

- Cấu hình HTTP liveness probe.
- Cấu hình file-based readiness probe bằng `exec`.
- Dùng startup probe cho ứng dụng warm-up chậm.
- Gây liveness failure có kiểm soát và quan sát kubelet restart đúng container.

## Nghiệp vụ thật

Deployment `pipeline-self-healing` dùng
`mualanhlung017/ai-data-pipeline:1.0.2`.

Init container chỉ làm nhiệm vụ compile `PipelineHealthServer.java`. Container
`health-api` chạy bằng Java runtime trong image project và chỉ tạo file
`/var/run/pipeline-health/ready` sau khi:

1. JAR `/opt/flink/usrlib/ai-data-pipeline.jar` tồn tại và có SHA-256 hợp lệ.
2. Flink trả thành công từ `/jobs/overview`.
3. Iceberg REST trả danh sách bảng medallion.
4. MinIO readiness endpoint trả HTTP 2xx.

Snapshot thật được phục vụ tại `/business`. Container
`readiness-reporter` đọc cùng `emptyDir` và log snapshot qua HTTP nội bộ.

## Ba probe khác nhau

```yaml
startupProbe:
  httpGet:
    path: /live
    port: http
  periodSeconds: 2
  failureThreshold: 20

readinessProbe:
  exec:
    command:
      - /usr/bin/test
      - -s
      - /var/run/pipeline-health/ready

livenessProbe:
  httpGet:
    path: /live
    port: http
  periodSeconds: 3
  failureThreshold: 2
```

- Startup probe cho tối đa 40 giây warm-up. Liveness/readiness chưa chạy cho
  tới khi startup probe thành công.
- Readiness thất bại làm Pod rời Service endpoints nhưng không restart
  container.
- Liveness thất bại liên tiếp khiến kubelet restart riêng `health-api`.

## Chạy từng bước

```cmd
kubectl apply --dry-run=server -f .\lab-5.1-self-healing.yaml
kubectl apply -f .\lab-5.1-self-healing.yaml
kubectl rollout status deployment/pipeline-self-healing -n data-platform --timeout=180s
```

Lấy Pod:

```cmd
for /f %P in ('kubectl get pod -n data-platform -l lab=5.1 -o jsonpath="{.items[0].metadata.name}"') do set POD=%P
kubectl get pod %POD% -n data-platform
kubectl exec %POD% -n data-platform -c health-api -- test -s /var/run/pipeline-health/ready
```

Đọc snapshot qua Service:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- curl -fsS http://pipeline-self-healing:8080/business
```

## Gây lỗi và quan sát self-healing

```cmd
kubectl get pod %POD% -n data-platform -o jsonpath="{.status.containerStatuses[?(@.name=='health-api')].restartCount}"
kubectl exec %POD% -n data-platform -c health-api -- rm -f /var/run/pipeline-health/live
kubectl get pod %POD% -n data-platform -w
```

Sau hai HTTP liveness failure, restart count tăng. Khi container warm-up và
kiểm tra dependency lại, readiness file được tạo lại:

```cmd
kubectl wait -n data-platform --for=condition=Ready pod/%POD% --timeout=120s
kubectl logs %POD% -n data-platform -c health-api --previous
kubectl get events -n data-platform --field-selector involvedObject.name=%POD% --sort-by=.metadata.creationTimestamp
```

## Batch runner

```cmd
lab-5.1.bat run
lab-5.1.bat deploy
lab-5.1.bat break
lab-5.1.bat verify
lab-5.1.bat status
lab-5.1.bat cleanup
```

`run` tự deploy, chứng minh readiness, xóa liveness file, chờ restart count
tăng và yêu cầu Pod trở lại `Ready`.

## Cleanup

```cmd
lab-5.1.bat cleanup
```
