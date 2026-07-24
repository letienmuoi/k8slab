# Windows batch runners cho Lab 1.1–1.4

Các file `.bat` chạy từ Windows `cmd`, luôn chuyển về thư mục chứa script và chỉ thao tác resource có tên/label của từng lab trong namespace `data-platform`.

## Điều kiện trước khi chạy

```cmd
kubectl get deployment -n data-platform
```

Kafka, Flink, Iceberg REST và MinIO của project phải ở trạng thái `Available`/`Ready` tùy lab.

## Lab 1.1

```cmd
lab-1.1.bat run
lab-1.1.bat generate
lab-1.1.bat verify
lab-1.1.bat cleanup
```

`run` tự export `pod-60.generated.yaml` bằng `kubectl run --dry-run=client -o yaml`, tạo Pod, đợi đủ 60 giây và in sáu snapshot Flink thật. File generated được giữ lại để luyện đọc YAML; Git bỏ qua file này.

## Lab 1.2

```cmd
lab-1.2.bat run
lab-1.2.bat verify
lab-1.2.bat cleanup
```

`run` reset ConfigMap/Pod, chờ init container và app hoàn thành, sau đó đọc application log qua sidecar. Sidecar vẫn chạy sau khi app hoàn thành nên cần gọi `cleanup` khi học xong.

## Lab 1.3

```cmd
lab-1.3.bat run
lab-1.3.bat job
lab-1.3.bat cronjob
lab-1.3.bat verify
lab-1.3.bat resume
lab-1.3.bat suspend
lab-1.3.bat cleanup
```

`run` chạy one-off Job, tạo CronJob, chờ scheduler sinh một Job ở đầu phút tiếp theo, chờ Job đó hoàn thành rồi tự đặt `suspend=true`. Vì vậy script chứng minh schedule thật nhưng không để CronJob tiếp tục ghi record mỗi phút.

## Lab 1.4

```cmd
lab-1.4.bat run
lab-1.4.bat reset
lab-1.4.bat query
lab-1.4.bat mutate
lab-1.4.bat verify
lab-1.4.bat cleanup
```

`run` thực hiện trọn drill: bulk-create sáu audit Pod, query equality/set-based selector, cố ý chạy một label update thiếu `--overwrite`, chạy lại đúng cách, cập nhật annotation và kiểm tra số object cuối.

Nếu muốn chạy từng phần, thứ tự là:

```cmd
lab-1.4.bat reset
lab-1.4.bat query
lab-1.4.bat mutate
lab-1.4.bat verify
```

## Lab 2.1

```cmd
lab-2.1.bat run
lab-2.1.bat deploy
lab-2.1.bat update
lab-2.1.bat bad
lab-2.1.bat rollback
lab-2.1.bat verify
lab-2.1.bat cleanup
```

`run` deploy ba replica bằng image `1.0.1`, rolling update lên `1.0.2`, simulate một image tag không tồn tại, xác nhận rollout timeout rồi rollback về `1.0.2`. Deployment lab audit Flink, Iceberg và MinIO thật; nó không thay đổi Deployment streaming của project.

## Lab 2.2

```cmd
lab-2.2.bat run
lab-2.2.bat deploy
lab-2.2.bat switch-green
lab-2.2.bat switch-blue
lab-2.2.bat verify
lab-2.2.bat cleanup
```

`run` deploy đồng thời blue `1.0.1` và green `1.0.2`, xác minh Service ban đầu route vào blue rồi flip selector sang green. Cả hai release gateway gọi Flink, Iceberg và MinIO thật; switch traffic không restart Pod.

## Lab 2.3

```cmd
lab-2.3.bat run
lab-2.3.bat deploy
lab-2.3.bat scale10
lab-2.3.bat hpa
lab-2.3.bat load
lab-2.3.bat verify
lab-2.3.bat cleanup
lab-2.3.bat cleanup-metrics
```

`run` deploy LineNormalizer API thật, scale thủ công lên 10 replica, cấu hình HPA `min=2/max=10/CPU=50%` và chạy normalization load Job để quan sát Metrics API. Nếu cluster chưa có Metrics Server, script cài bản chính thức đã pin cho local lab.

## Lab 2.4

```cmd
lab-2.4.bat run
lab-2.4.bat render
lab-2.4.bat dev
lab-2.4.bat prod
lab-2.4.bat verify
lab-2.4.bat cleanup
```

`run` dùng một Deployment base để tạo dev `1.0.1/1 replica` và prod `1.0.2/3 replicas`. Các overlay chỉ khai báo image transformer, replica transformer và nhãn môi trường; workload tiếp tục audit Flink, Iceberg và MinIO thật.

## Lab 3.1

```cmd
lab-3.1.bat run
lab-3.1.bat create-config
lab-3.1.bat pod
lab-3.1.bat verify
lab-3.1.bat cleanup
```

`run` tạo Secret từ file và ConfigMap từ ba literal endpoint, sau đó inject Secret thành env và mount ConfigMap thành volume. Pod dùng cấu hình đó để audit Flink, Iceberg và MinIO thật mà không log plaintext token.

## Lab 3.2

```cmd
lab-3.2.bat run
lab-3.2.bat apply
lab-3.2.bat verify
lab-3.2.bat cleanup
```

`run` khóa project Pod ở UID/GID `10001`, root filesystem read-only, `allowPrivilegeEscalation=false`, drop `ALL` capabilities và dùng `emptyDir` giới hạn làm `/tmp` writable.

## Lab 3.3

```cmd
lab-3.3.bat run
lab-3.3.bat apply
lab-3.3.bat verify
lab-3.3.bat cleanup
```

`run` tạo ServiceAccount, Role và RoleBinding tối thiểu. Pod dùng projected token gọi Kubernetes API để list các Pod pipeline trong `data-platform`; kiểm tra âm xác nhận ServiceAccount không đọc được Secrets.

## Lab 3.4

```cmd
lab-3.4.bat run
lab-3.4.bat setup
lab-3.4.bat allowed
lab-3.4.bat reject
lab-3.4.bat verify
lab-3.4.bat cleanup
```

`run` tạo namespace `pipeline-quota-lab`, inject resources bằng LimitRange, cho phép Pod audit đầu tiên và yêu cầu API server từ chối Pod thứ hai với lỗi `exceeded quota`. Namespace production `data-platform` không bị áp quota.

## Lưu ý dữ liệu

Cleanup chỉ xóa Kubernetes resource của lab. Record mà Lab 1.2 và Lab 1.3 đã ghi vào Kafka/Iceberg là dữ liệu nghiệp vụ thật và không bị xóa.
