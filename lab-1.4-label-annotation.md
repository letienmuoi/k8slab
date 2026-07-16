# Lab 1.4: Label & Annotation Drill với nghiệp vụ thật

Thời lượng gợi ý: khoảng 30 phút. CKAD domain: Application Design and Build.

## Mục tiêu

- Bulk-create sáu Pod thực hiện operational audit thật trên data pipeline.
- Truy vấn resource bằng equality-based và set-based label selector.
- Thêm, đổi và xoá label trên nhiều object.
- Dùng `--overwrite` khi thay đổi label đã tồn tại.
- Phân biệt label với annotation.

## Sáu Pod làm gì?

Tất cả Pod nằm trong namespace `data-platform`, chạy một kiểm tra hữu hạn rồi chuyển sang `Completed`. Pod đã hoàn thành vẫn là Kubernetes object nên label và annotation vẫn có thể truy vấn hoặc cập nhật.

| Pod | Nghiệp vụ thật | `env` | `tier` | `track` | `component` |
|---|---|---|---|---|---|
| `audit-kafka-topics-dev` | Liệt kê Kafka topics | `dev` | `ingest` | `stable` | `kafka` |
| `audit-kafka-raw-prod` | Describe topic `raw-data` | `prod` | `ingest` | `stable` | `kafka` |
| `audit-flink-jobs-dev` | Liệt kê Flink jobs bằng CLI | `dev` | `process` | `stable` | `flink` |
| `audit-flink-api-prod` | Query Flink REST `/jobs/overview` | `prod` | `process` | `stable` | `flink` |
| `audit-iceberg-tables-dev` | Liệt kê Iceberg Medallion tables | `dev` | `serve` | `canary` | `iceberg` |
| `audit-minio-health-prod` | Kiểm tra MinIO readiness | `prod` | `serve` | `canary` | `minio` |

Không Pod nào dùng `sh -c`, `sleep` hoặc output giả. Manifest gọi trực tiếp Kafka CLI, Flink CLI và các HTTP API thật.

## Phần 0 — Kiểm tra stack

```cmd
kubectl get deployment -n data-platform
```

Cần thấy `kafka`, `flink-jobmanager`, `flink-taskmanager`, `iceberg-rest` và `minio` đều `READY`.

## Phần 1 — Bulk-create sáu Pod

```cmd
kubectl apply -f .\lab-1.4-label-annotation.yaml
kubectl wait -n data-platform --for=jsonpath="{.status.phase}"=Succeeded pod -l lab=1.4 --timeout=180s
kubectl get pods -n data-platform -l lab=1.4 -L env,tier,track,component
```

Kết quả mong đợi: sáu Pod có `STATUS=Completed` và label đúng theo bảng.

Xem output nghiệp vụ của tất cả Pod:

```cmd
kubectl logs -n data-platform -l lab=1.4 --prefix=true --tail=80 --max-log-requests=6
```

Trong log cần thấy:

- Kafka topics `raw-data` và `refined-data`.
- Flink job ở trạng thái `RUNNING`.
- Iceberg tables `bronze_lines`, `silver_lines`, `gold_ai_ready`.
- `minio_ready_http=200`.

Không dùng `--all` cho lệnh update vì namespace còn workload thật của project. Luôn giới hạn bằng `-l lab=1.4`.

## Phần 2 — Query bằng label selector

Xem toàn bộ label:

```cmd
kubectl get pods -n data-platform -l lab=1.4 --show-labels
```

Equality và inequality:

```cmd
kubectl get pods -n data-platform -l "lab=1.4,env=dev"
kubectl get pods -n data-platform -l "lab=1.4,env=prod,tier=serve"
kubectl get pods -n data-platform -l "lab=1.4,component=flink"
kubectl get pods -n data-platform -l "lab=1.4,env!=prod"
```

Set-based selector:

```cmd
kubectl get pods -n data-platform -l "lab=1.4,component in (kafka,flink)"
kubectl get pods -n data-platform -l "lab=1.4,env in (dev,prod),tier notin (serve)"
kubectl get pods -n data-platform -l "lab=1.4,track"
```

Quy tắc cần nhớ:

- Dấu phẩy giữa các điều kiện là AND.
- `in (...)` khớp một trong nhiều value của cùng một key.
- Không có OR giữa hai label key khác nhau.
- `track` đứng một mình nghĩa là key đó phải tồn tại.
- Trong Windows `cmd`, selector có khoảng trắng hoặc dấu ngoặc nên đặt trong dấu nháy kép.

## Phần 3 — Bulk-update label

Thêm owner cho cả sáu audit Pod:

```cmd
kubectl label pods -n data-platform -l lab=1.4 owner=franc
kubectl get pods -n data-platform -l lab=1.4 -L owner
```

Thử đổi ba object `env=dev` thành `env=test` khi chưa cho phép overwrite:

```cmd
kubectl label pods -n data-platform -l "lab=1.4,env=dev" env=test
```

Lệnh trên phải thất bại với thông báo `env` đã có giá trị và `--overwrite` là `false`. Chạy lại đúng cách:

```cmd
kubectl label pods -n data-platform -l "lab=1.4,env=dev" env=test --overwrite
kubectl get pods -n data-platform -l lab=1.4 -L env,tier,track,component,owner
```

Gắn `team=data` cho hai tier nghiệp vụ `ingest` và `process`:

```cmd
kubectl label pods -n data-platform -l "lab=1.4,tier in (ingest,process)" team=data
kubectl get pods -n data-platform -l lab=1.4 -L tier,component,team
```

Đổi `track=stable` thành `track=blue`:

```cmd
kubectl label pods -n data-platform -l "lab=1.4,track=stable" track=blue --overwrite
```

Xoá label `track` khỏi một audit Pod, sau đó query object không có key này:

```cmd
kubectl label pod audit-iceberg-tables-dev -n data-platform track-
kubectl get pods -n data-platform -l "lab=1.4,!track"
```

Hậu tố `-` trong `track-` nghĩa là xoá label và không cần `--overwrite`.

## Phần 4 — Annotation drill

Thêm annotation owner hàng loạt dựa trên label selector:

```cmd
kubectl annotate pods -n data-platform -l lab=1.4 lab.muoilt.vn/owner=franc
```

Đổi annotation đã tồn tại:

```cmd
kubectl annotate pods -n data-platform -l lab=1.4 lab.muoilt.vn/owner="franc-nguyen" --overwrite
kubectl get pods -n data-platform -l lab=1.4 -o custom-columns="NAME:.metadata.name,OWNER:.metadata.annotations.lab\.muoilt\.vn/owner"
```

Label chứa metadata nhận diện để select và nhóm object. Annotation chứa metadata mô tả như owner, runbook URL, build ID hoặc ghi chú; annotation không dùng được với `kubectl get -l`.

## Phần 5 — Tự kiểm tra

Sau toàn bộ thay đổi, chạy:

```cmd
kubectl get pods -n data-platform -l "lab=1.4,env=prod,tier=serve" --no-headers
kubectl get pods -n data-platform -l "lab=1.4,env=test" --no-headers
kubectl get pods -n data-platform -l "lab=1.4,team=data" --no-headers
kubectl get pods -n data-platform -l "lab=1.4,!track" --no-headers
```

Số dòng mong đợi lần lượt là `1`, `3`, `4`, `1`.

Ma trận cuối:

```cmd
kubectl get pods -n data-platform -l lab=1.4 -L env,tier,track,component,owner,team
```

## Reset và cleanup

Muốn làm lại từ đầu:

```cmd
kubectl delete pods -n data-platform -l lab=1.4
kubectl apply -f .\lab-1.4-label-annotation.yaml
```

Kết thúc lab:

```cmd
kubectl delete pods -n data-platform -l lab=1.4
```

Cleanup chỉ xoá sáu audit Pod, không xoá Kafka, Flink, Iceberg, MinIO hoặc dữ liệu pipeline.

