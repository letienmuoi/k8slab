# Lab 2.1: Rolling Update & Rollback với pipeline thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Deployment.

## Mục tiêu

- Deploy release `v1` bằng Deployment có ba replica.
- Rolling update image thật từ `1.0.1` lên `1.0.2`.
- Theo dõi rollout bằng `kubectl rollout status`, Pods và ReplicaSets.
- Simulate bad deployment bằng image tag không tồn tại.
- Roll back về release `v2` đang hoạt động.

## Nghiệp vụ của Deployment

Lab tạo Deployment độc lập `pipeline-release-auditor`; nó không thay đổi hai Deployment Flink đang chạy production.

Mỗi replica dùng image thật của project và cứ 15 giây thực hiện:

```text
pipeline-release-auditor
  -> kiểm tra JAR /opt/flink/usrlib/ai-data-pipeline.jar
  -> query Flink /jobs/overview
  -> query Iceberg namespace medallion
  -> query MinIO readiness
  -> ghi response thật và SHA-256 của JAR ra log
```

Hai release chứa hai artifact JAR khác nhau:

```text
v1 = mualanhlung017/ai-data-pipeline:1.0.1
v2 = mualanhlung017/ai-data-pipeline:1.0.2
```

Readiness probe cũng gọi ba endpoint thật. Pod chỉ tham gia vào số replica `Ready` khi artifact tồn tại và Flink, Iceberg, MinIO đều truy cập được.

## RollingUpdate strategy

Manifest cấu hình:

```yaml
replicas: 3
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

- `maxUnavailable: 0`: Kubernetes không chủ động làm giảm số Pod sẵn sàng xuống dưới ba trong rollout.
- `maxSurge: 1`: được tạo tối đa một Pod mới vượt quá desired replicas.
- Khi Pod mới `Ready`, controller mới scale down Pod cũ.

## Phần 0 — Precheck

```cmd
kubectl get deployment flink-jobmanager flink-taskmanager iceberg-rest minio -n data-platform
```

Các dependency phải `Available`. Validate manifest:

```cmd
kubectl apply --dry-run=client -f .\lab-2.1-rolling-update.yaml
kubectl apply --dry-run=server -f .\lab-2.1-rolling-update.yaml
```

## Phần 1 — Deploy v1

```cmd
kubectl apply -f .\lab-2.1-rolling-update.yaml
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=120s
```

Kiểm tra image, Pod và log nghiệp vụ:

```cmd
kubectl get deployment pipeline-release-auditor -n data-platform
kubectl get pods -n data-platform -l lab=2.1 -o wide
kubectl get deployment pipeline-release-auditor -n data-platform -o jsonpath="{.spec.template.spec.containers[0].image}"
kubectl logs -n data-platform -l lab=2.1 --prefix=true --tail=8 --max-log-requests=4
```

Log `event=auditor_started` chứa SHA-256 của JAR v1. Log audit phải có:

- Flink job state `RUNNING`.
- Iceberg tables `bronze_lines`, `silver_lines`, `gold_ai_ready`.
- `minio_http=200`.

Xem revision đầu:

```cmd
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
```

## Phần 2 — Rolling update v1 → v2

Trong cửa sổ `cmd` thứ nhất, theo dõi Pod:

```cmd
kubectl get pods -n data-platform -l lab=2.1 -w
```

Trong cửa sổ thứ hai, đổi image rồi ghi change cause cho revision mới:

```cmd
kubectl set image deployment/pipeline-release-auditor auditor=mualanhlung017/ai-data-pipeline:1.0.2 -n data-platform
kubectl annotate deployment pipeline-release-auditor -n data-platform kubernetes.io/change-cause="Rolling update auditor from 1.0.1 to 1.0.2" --overwrite
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=120s
```

Nhấn `Ctrl+C` ở cửa sổ watch sau khi rollout hoàn tất.

Exam-speed verification:

```cmd
kubectl get deployment pipeline-release-auditor -n data-platform -o jsonpath="{.spec.template.spec.containers[0].image}"
kubectl get pods -n data-platform -l lab=2.1 -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID"
kubectl get rs -n data-platform -l lab=2.1
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
kubectl logs -n data-platform -l lab=2.1 --prefix=true --tail=8 --max-log-requests=4
```

Kết quả cần thấy:

- Deployment image là `1.0.2`.
- Ba Pod mới đều `Ready`.
- ReplicaSet v2 có desired/current/ready bằng ba.
- SHA-256 trong log v2 khác v1.

Trong lúc watch, Pod v1 có thể còn hiển thị `Terminating` vài giây vì lab có `preStop` và termination grace. Đây là shutdown có kiểm soát, không phải rollout bị kẹt.

## Phần 3 — Simulate bad deployment

Deploy tag chắc chắn không tồn tại rồi ghi change cause cho revision xấu:

```cmd
kubectl set image deployment/pipeline-release-auditor auditor=mualanhlung017/ai-data-pipeline:ckad-bad-does-not-exist -n data-platform
kubectl annotate deployment pipeline-release-auditor -n data-platform kubernetes.io/change-cause="Simulate bad release with missing image" --overwrite
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=25s
```

Lệnh `rollout status` phải timeout; đây là expected failure của bài.

Kiểm tra nguyên nhân:

```cmd
kubectl get deployment pipeline-release-auditor -n data-platform
kubectl get pods -n data-platform -l lab=2.1 -o wide
kubectl get rs -n data-platform -l lab=2.1
kubectl describe deployment pipeline-release-auditor -n data-platform
```

Kết quả quan trọng:

- Một Pod release xấu ở `ErrImagePull` hoặc `ImagePullBackOff`.
- Ba Pod v2 cũ vẫn `Running/Ready`.
- Có thể thấy tổng cộng bốn Pod vì `maxSurge=1`.
- `AVAILABLE` vẫn là ba do `maxUnavailable=0`.

Đây là lý do RollingUpdate giúp giảm tác động của release xấu: controller không xóa replica v2 khỏe mạnh khi replica mới chưa qua readiness.

## Phần 4 — Rollback

Xem lịch sử:

```cmd
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
```

Rollback về revision trước:

```cmd
kubectl rollout undo deployment/pipeline-release-auditor -n data-platform
kubectl annotate deployment pipeline-release-auditor -n data-platform kubernetes.io/change-cause="Rollback missing image to ai-data-pipeline:1.0.2" --overwrite
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=120s
```

Verify:

```cmd
kubectl get deployment pipeline-release-auditor -n data-platform -o jsonpath="{.spec.template.spec.containers[0].image}"
kubectl get pods -n data-platform -l lab=2.1
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
kubectl logs -n data-platform -l lab=2.1 --prefix=true --tail=8 --max-log-requests=4
```

Image phải trở lại:

```text
mualanhlung017/ai-data-pipeline:1.0.2
```

Không rollback về `1.0.1`, vì “previous revision” ngay trước bad release là v2.

Deployment ban đầu được tạo bằng `kubectl apply`, sau đó được thay đổi bằng các lệnh imperative. Vì vậy một số phiên bản `kubectl` có thể cảnh báo `rollout undo` không cập nhật annotation `kubectl.kubernetes.io/last-applied-configuration`. Rollback vẫn hợp lệ; annotation này chỉ ảnh hưởng lần `kubectl apply` sau. Cleanup rồi apply lại manifest sẽ reset lab về v1.

Sau rollback, ReplicaSet v2 cũ được dùng lại và nhận revision mới. Vì vậy history có thể hiển thị `1, 3, 4` thay vì giữ revision `2`.

## Lệnh CKAD cần nhớ

```cmd
kubectl set image deployment/NAME CONTAINER=IMAGE
kubectl rollout status deployment/NAME
kubectl rollout history deployment/NAME
kubectl rollout undo deployment/NAME
kubectl rollout undo deployment/NAME --to-revision=N
```

Nếu cần rollback đến một revision cụ thể, đọc số revision từ `rollout history`, sau đó dùng `--to-revision`.

## Batch runner

Chạy toàn bộ lab:

```cmd
lab-2.1.bat run
```

Hoặc từng phần:

```cmd
lab-2.1.bat deploy
lab-2.1.bat update
lab-2.1.bat bad
lab-2.1.bat rollback
lab-2.1.bat verify
lab-2.1.bat cleanup
```

## Cleanup

```cmd
kubectl delete deployment pipeline-release-auditor -n data-platform --ignore-not-found
```

Cleanup chỉ xóa Deployment/ReplicaSets/Pods của Lab 2.1; Kafka, Flink, Iceberg, MinIO và dữ liệu pipeline không bị thay đổi.
