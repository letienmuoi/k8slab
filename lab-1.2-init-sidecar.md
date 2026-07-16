# Lab 1.2: Init + Sidecar Pattern với pipeline thật

Thời lượng gợi ý: khoảng 60 phút. CKAD domain: Application Design and Build.

## Mục tiêu

- Tạo Pod gồm một init container, một app container và một sidecar.
- Dùng `emptyDir` để bàn giao input/SQL và chia sẻ application log.
- Ingest file thật vào Kafka `raw-data` bằng Flink SQL Client.
- Đọc log app thông qua `kubectl logs -c sidecar`.
- Kiểm tra record đã được `MedallionPipelineJob` chuẩn hoá trong `refined-data`.

## Luồng nghiệp vụ

```text
ConfigMap (input.txt + pipeline.sql)
              |
              v
init container: prepare-pipeline
  -> copy input + SQL vào emptyDir pipeline-work
  -> tạo app.log trong emptyDir pipeline-logs
              |
              v
app container
  -> Flink SQL đọc /work/input.txt
  -> INSERT vào Kafka raw-data
  -> ghi log thật vào /var/log/pipeline/app.log
              |
              +--------------------+
              |                    |
              v                    v
sidecar tail app.log       Deployment Flink của project
                           -> LineNormalizer
                           -> refined-data + Iceberg
```

Không còn vòng lặp tạo message giả. Shell chỉ thực hiện setup file và redirect log của SQL Client.

## Hai `emptyDir` có vai trò gì?

| Volume | Container ghi | Container đọc | Dữ liệu |
|---|---|---|---|
| `pipeline-work` | init | app, sidecar | `input.txt`, `pipeline.sql` |
| `pipeline-logs` | init/app | sidecar | `app.log` |

`emptyDir` được tạo cùng Pod, tồn tại qua việc container kết thúc/restart, và bị xoá khi Pod bị xoá.

## Phần 0 — Kiểm tra stack thật

```cmd
kubectl get deployment -n data-platform
```

Cần thấy Kafka và hai Deployment Flink đều `READY`.

## Phần 1 — Tạo ConfigMap và Pod

Manifest chứa cả ConfigMap lẫn Pod:

```cmd
kubectl apply -f .\lab-1.2-init-sidecar.yaml
```

Chờ init container hoàn thành:

```cmd
kubectl wait -n data-platform --for=condition=Initialized pod/pipeline-init-sidecar-demo --timeout=120s
kubectl get pod pipeline-init-sidecar-demo -n data-platform -o jsonpath="{.status.initContainerStatuses[0].state.terminated.reason}"
```

Kết quả cần thấy là `Completed`.

Chờ app thực hiện xong Flink SQL:

```cmd
kubectl wait -n data-platform --for=jsonpath="{.status.containerStatuses[?(@.name=='app')].state.terminated.exitCode}"=0 pod/pipeline-init-sidecar-demo --timeout=180s
```

## Phần 2 — Quan sát trạng thái multi-container

```cmd
kubectl get pod pipeline-init-sidecar-demo -n data-platform
kubectl get pod pipeline-init-sidecar-demo -n data-platform -o jsonpath="{range .status.containerStatuses[*]}{.name}{'='}{.state}{' '}{end}"
```

Trạng thái mong đợi:

- Init container: `Completed`, exit code `0`.
- App container: `Completed`, exit code `0`.
- Sidecar: `Running` vì đang tail log.
- Pod có thể hiển thị `1/2 NotReady`; đây không phải lỗi. App hữu hạn đã hoàn thành còn sidecar vẫn chạy.

## Phần 3 — Chứng minh init bàn giao dữ liệu qua `emptyDir`

Sidecar được mount read-only `pipeline-work`, nên dùng nó để kiểm tra dữ liệu init đã chuẩn bị:

```cmd
kubectl exec pipeline-init-sidecar-demo -n data-platform -c sidecar -- cat /work/input.txt
kubectl exec pipeline-init-sidecar-demo -n data-platform -c sidecar -- cat /work/pipeline.sql
```

Liệt kê volume và mount:

```cmd
kubectl get pod pipeline-init-sidecar-demo -n data-platform -o jsonpath="{.spec.volumes[*].name}"
kubectl describe pod pipeline-init-sidecar-demo -n data-platform
```

## Phần 4 — Đọc application log từ sidecar

```cmd
kubectl logs pipeline-init-sidecar-demo -n data-platform -c sidecar
```

Log phải chứa SQL thật và dòng:

```text
Complete execution of the SQL update statement.
```

App redirect stdout/stderr vào shared file nên lệnh sau được phép không in gì:

```cmd
kubectl logs pipeline-init-sidecar-demo -n data-platform -c app
```

Đọc trực tiếp cùng file mà sidecar đang tail:

```cmd
kubectl exec pipeline-init-sidecar-demo -n data-platform -c sidecar -- cat /var/log/pipeline/app.log
```

Điểm cần nhớ: `kubectl logs -c sidecar` đọc stdout của process `tail`; stdout đó có nguồn gốc từ file log app trong `emptyDir`.

## Phần 5 — Xác minh pipeline end-to-end

Deployment Flink đang chạy sẽ đọc ba dòng từ `raw-data`, gọi `LineNormalizer` thật và ghi `refined-data`.

```cmd
kubectl exec -n data-platform deployment/kafka -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic refined-data --from-beginning --timeout-ms 10000 2>nul | findstr /I "LAB12"
```

Kết quả mong đợi có ba record, ví dụ:

```json
{"original_line":"  LAB12    HELLO AI DATA PIPELINE","normalized_line":"lab12 hello ai data pipeline","character_count":28,...}
{"original_line":"Apache NIFI to KAFKA FROM LAB12","normalized_line":"apache nifi to kafka from lab12","character_count":31,...}
{"original_line":"FLINK writes ICEBERG on MINIO LAB12","normalized_line":"flink writes iceberg on minio lab12","character_count":35,...}
```

## Những lỗi thường gặp

- ConfigMap chưa tồn tại: init container bị kẹt ở `CreateContainerConfigError`.
- Kafka/Flink stack chưa sẵn sàng: app log có lỗi connector và app thoát khác `0`.
- Sai quyền `emptyDir`: init không thể tạo file. Manifest dùng `fsGroup: 9999`, trùng group của user `flink` trong image.
- Dùng `kubectl logs` mà không có `-c`: Kubernetes yêu cầu chọn container vì Pod có nhiều container.
- Pod không tự `Completed`: sidecar được thiết kế chạy liên tục; phải cleanup thủ công.

## Cleanup

```cmd
kubectl delete -f .\lab-1.2-init-sidecar.yaml
```

Khi Pod bị xoá, hai `emptyDir` và file log biến mất. Các record đã ghi vào Kafka/Iceberg là dữ liệu thật nên vẫn được giữ lại.

