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

## Lưu ý dữ liệu

Cleanup chỉ xóa Kubernetes resource của lab. Record mà Lab 1.2 và Lab 1.3 đã ghi vào Kafka/Iceberg là dữ liệu nghiệp vụ thật và không bị xóa.
