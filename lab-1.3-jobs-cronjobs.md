# Lab 1.3: Jobs & CronJobs với pipeline thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Design and Build.

## Mục tiêu

- Chạy một Job hữu hạn đến trạng thái `Complete` với `backoffLimit`.
- Tạo CronJob sinh Job theo lịch.
- Đưa record thật vào Kafka và quan sát Flink pipeline xử lý.
- Phân biệt vai trò Job/CronJob với Deployment chạy streaming liên tục.

## Logic thật lấy từ project

Source tham chiếu:

```text
C:\Users\franc\source\muoilt_k8sproj
```

`MedallionPipelineJob` trong project là streaming job không tự kết thúc. Nó đọc Kafka topic `raw-data`, gọi `LineNormalizer` để chuẩn hoá Unicode/case/whitespace, sau đó ghi `refined-data` và các bảng Iceberg Bronze/Silver/Gold.

Vì vậy Lab 1.3 chia trách nhiệm đúng theo kiến trúc thật:

```text
Job/CronJob hữu hạn
  -> Flink SQL Client INSERT record vào Kafka raw-data
  -> Job Complete

Deployment flink-jobmanager + flink-taskmanager chạy liên tục
  -> đọc raw-data
  -> LineNormalizer thật
  -> refined-data + Iceberg Bronze/Silver/Gold
```

Không còn shell giả lập `echo/sleep`. Container chạy trực tiếp:

```text
/opt/flink/bin/sql-client.sh embedded -Dexecution.target=local --file <SQL file>
```

SQL dùng Kafka connector thật đã có trong image `mualanhlung017/ai-data-pipeline:1.0.2`.

## Ba file của lab

- `lab-1.3-pipeline-sql.yaml`: ConfigMap chứa SQL hữu hạn cho Job và CronJob.
- `lab-1.3-job.yaml`: one-off Job.
- `lab-1.3-cronjob.yaml`: CronJob chạy mỗi phút.

Tất cả resource của lab nằm trong namespace `data-platform`, cùng Kafka và Flink của project.

## Phần 0 — Kiểm tra stack thật

```cmd
kubectl get deployment -n data-platform
```

Cần thấy các Deployment `kafka`, `iceberg-rest`, `minio`, `nifi`, `flink-jobmanager` và `flink-taskmanager` đều `READY`.

Nếu stack chưa tồn tại:

```cmd
cd C:\Users\franc\source\muoilt_k8sproj
kubectl apply -k .
kubectl rollout status deployment/kafka -n data-platform --timeout=180s
kubectl rollout status deployment/flink-jobmanager -n data-platform --timeout=300s
kubectl rollout status deployment/flink-taskmanager -n data-platform --timeout=300s
cd C:\Users\franc\source\muoilt_k8slab
```

## Phần 1 — One-off Job

Tạo ConfigMap SQL trước, sau đó tạo Job:

```cmd
kubectl apply -f .\lab-1.3-pipeline-sql.yaml
kubectl apply -f .\lab-1.3-job.yaml
```

Chờ hoàn thành và kiểm tra:

```cmd
kubectl wait -n data-platform --for=condition=complete job/ai-data-pipeline-once --timeout=240s
kubectl get job ai-data-pipeline-once -n data-platform
kubectl logs job/ai-data-pipeline-once -n data-platform
```

Trong log cần có:

```text
Complete execution of the SQL update statement.
```

Job gửi hai raw record thật:

```text
  LAB13 ONE-OFF   HELLO AI
KUBERNETES JOB RUNS ONCE
```

Đọc topic `refined-data` và chỉ giữ record của lab:

```cmd
kubectl exec -n data-platform deployment/kafka -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic refined-data --from-beginning --timeout-ms 10000 2>nul | findstr /I "LAB13 KUBERNETES"
```

Kết quả phải chứa logic chuẩn hoá thật, ví dụ:

```json
{"original_line":"  LAB13 ONE-OFF   HELLO AI  ","normalized_line":"lab13 one-off hello ai","character_count":22,...}
{"original_line":"KUBERNETES JOB RUNS ONCE","normalized_line":"kubernetes job runs once","character_count":24,...}
```

Kiểm tra field CKAD:

```cmd
kubectl get job ai-data-pipeline-once -n data-platform -o jsonpath="{.spec.backoffLimit}"
kubectl get job ai-data-pipeline-once -n data-platform -o jsonpath="{.spec.template.spec.restartPolicy}"
kubectl describe job ai-data-pipeline-once -n data-platform
```

Giá trị cần thấy lần lượt là `3` và `Never`.

- `backoffLimit: 3`: Job controller retry khi Pod thất bại và dừng khi chạm giới hạn.
- `restartPolicy: Never`: một Pod lỗi không restart container tại chỗ; Job controller tạo Pod thay thế khi còn retry.
- `activeDeadlineSeconds: 180`: Job không được chạy vô hạn khi Kafka hoặc SQL có vấn đề.

Job đã `Complete` không chạy lại khi apply cùng tên. Muốn chạy lại:

```cmd
kubectl delete job ai-data-pipeline-once -n data-platform
kubectl apply -f .\lab-1.3-job.yaml
```

## Phần 2 — CronJob

Tạo CronJob chạy mỗi phút:

```cmd
kubectl apply -f .\lab-1.3-cronjob.yaml
kubectl get cronjob ai-data-pipeline-schedule -n data-platform
```

Mỗi Job con tạo một record có thời gian thực, ví dụ:

```text
  LAB13 CRONJOB REAL RUN 2026-07-16 02:08:13.557
```

Các field chính:

- `schedule: "*/1 * * * *"`: chạy mỗi phút.
- `timeZone: Asia/Ho_Chi_Minh`: lịch theo giờ Việt Nam.
- `concurrencyPolicy: Forbid`: không tạo lần chạy chồng nhau từ cùng CronJob.
- `successfulJobsHistoryLimit: 3`: giữ ba Job thành công gần nhất.
- `failedJobsHistoryLimit: 1`: giữ một Job thất bại gần nhất.
- `jobTemplate.spec.backoffLimit: 2`: retry policy của từng Job con.

Tạo ngay một Job từ template mà không cần đợi lịch:

```cmd
kubectl create job ai-data-pipeline-manual -n data-platform --from=cronjob/ai-data-pipeline-schedule
kubectl wait -n data-platform --for=condition=complete job/ai-data-pipeline-manual --timeout=240s
kubectl logs job/ai-data-pipeline-manual -n data-platform
```

Job thủ công chỉ kiểm tra `jobTemplate`. Để chứng minh scheduler hoạt động, đợi cột `LAST SCHEDULE` có giá trị và xuất hiện Job tên `ai-data-pipeline-schedule-<timestamp>`:

```cmd
kubectl get cronjob,job -n data-platform -l lab=1.3
kubectl get pods -n data-platform -l app=ai-data-pipeline,workload=scheduled
```

Kiểm tra output đã đi qua `LineNormalizer` thật:

```cmd
kubectl exec -n data-platform deployment/kafka -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic refined-data --from-beginning --timeout-ms 10000 2>nul | findstr /I "LAB13 CRONJOB"
```

Giá trị `normalized_line` phải viết thường, bỏ khoảng trắng đầu/cuối và gộp khoảng trắng liên tiếp.

Tạm dừng và bật lại lịch từ Windows `cmd`:

```cmd
kubectl patch cronjob ai-data-pipeline-schedule -n data-platform -p "{\"spec\":{\"suspend\":true}}"
kubectl get cronjob ai-data-pipeline-schedule -n data-platform
kubectl patch cronjob ai-data-pipeline-schedule -n data-platform -p "{\"spec\":{\"suspend\":false}}"
```

## Job/CronJob khác Deployment trong chính project này thế nào?

| Resource | Vai trò thật trong lab | Trạng thái đích |
|---|---|---|
| Job | Gửi một batch record hữu hạn vào Kafka | `Complete` |
| CronJob | Theo lịch tạo Job gửi một batch record | Mỗi Job con `Complete` hoặc `Failed` |
| Deployment Flink | Liên tục đọc Kafka, normalize và ghi Kafka/Iceberg | Luôn `Available`, không `Complete` |

Nếu chạy `MedallionPipelineJob` trực tiếp trong Job/CronJob, nó sẽ không hoàn thành vì source Kafka là unbounded. Đó là lý do streaming pipeline thật vẫn thuộc Deployment, còn Job/CronJob đảm nhiệm tác vụ hữu hạn.

## Cleanup

```cmd
kubectl delete job ai-data-pipeline-manual -n data-platform --ignore-not-found
kubectl delete -f .\lab-1.3-cronjob.yaml --ignore-not-found
kubectl delete -f .\lab-1.3-job.yaml --ignore-not-found
kubectl delete -f .\lab-1.3-pipeline-sql.yaml --ignore-not-found
```

Cleanup chỉ xoá resource của lab. Các record đã ghi vào Kafka/Iceberg là dữ liệu thật nên vẫn được giữ lại; chạy lab nhiều lần sẽ tạo thêm record.
