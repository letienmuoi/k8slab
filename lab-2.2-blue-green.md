# Lab 2.2: Blue/Green Switch với pipeline thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Deployment.

## Mục tiêu

- Chạy đồng thời hai Deployment `blue` và `green`.
- Dùng một Service duy nhất làm stable traffic entrypoint.
- Chuyển traffic bằng cách flip `spec.selector.track`.
- Kiểm tra EndpointSlices và response trước/sau khi switch.
- Chuyển ngược về blue mà không rollout lại Pod.

## Nghiệp vụ thật

Lab dùng hai image release thật của project:

| Môi trường | Deployment | Image | Release label |
|---|---|---|---|
| Blue | `pipeline-release-blue` | `mualanhlung017/ai-data-pipeline:1.0.1` | `v1` |
| Green | `pipeline-release-green` | `mualanhlung017/ai-data-pipeline:1.0.2` | `v2` |

Mỗi Pod có init container `eclipse-temurin:17-jdk-jammy` compile `ReleaseGateway.java` vào `emptyDir`. Main container vẫn là image project `1.0.1` hoặc `1.0.2`; nó chạy class đã biên dịch bằng Java runtime có sẵn trong image. HTTP response gồm:

- `color` và `release` đang nhận traffic.
- Pod name.
- SHA-256 của `/opt/flink/usrlib/ai-data-pipeline.jar`.
- Flink job state thật.
- Danh sách Iceberg Medallion table thật.
- MinIO readiness HTTP status thật.

Readiness probe gọi `/ready`; endpoint này chỉ trả `200` khi Flink, Iceberg và MinIO đều truy cập được.

`emptyDir` chỉ chứa class runtime của từng Pod và biến mất khi Pod bị xóa. Init compiler không xử lý traffic.

```text
                         +--> Deployment blue (1.0.1, 2 Pods)
Service stable endpoint |
selector track=<color>   +--> Deployment green (1.0.2, 2 Pods)
```

Hai Deployment luôn chạy song song. Switch không thay image, không restart Pod và không đổi địa chỉ Service.

## Phần 0 — Precheck và validate

```cmd
kubectl get deployment flink-jobmanager flink-taskmanager iceberg-rest minio -n data-platform
kubectl apply --dry-run=client -f .\lab-2.2-blue-green.yaml
kubectl apply --dry-run=server -f .\lab-2.2-blue-green.yaml
```

## Phần 1 — Deploy blue và green

```cmd
kubectl apply -f .\lab-2.2-blue-green.yaml
kubectl rollout status deployment/pipeline-release-blue -n data-platform --timeout=180s
kubectl rollout status deployment/pipeline-release-green -n data-platform --timeout=180s
```

Kiểm tra cả bốn Pod:

```cmd
kubectl get deployment pipeline-release-blue pipeline-release-green -n data-platform
kubectl get pods -n data-platform -l lab=2.2 -L track,release
```

Kết quả cần thấy:

- Blue `2/2 Ready`.
- Green `2/2 Ready`.
- Hai màu có Pod name và ReplicaSet khác nhau.

## Phần 2 — Service đang route vào blue

Đọc selector:

```cmd
kubectl get service pipeline-release-gateway -n data-platform -o jsonpath="{.spec.selector}"
```

Giá trị quan trọng là:

```text
track: blue
```

Xem EndpointSlice:

```cmd
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-release-gateway
kubectl describe service pipeline-release-gateway -n data-platform
```

Gọi stable Service từ một Pod thật của project:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-release-gateway:8080/
```

Response phải có:

```text
color=blue
release=1.0.1
minio_http=200
```

`jar_sha256` của blue phải tương ứng JAR trong image `1.0.1`.

## Phần 3 — Flip traffic sang green

Chỉ patch một label selector:

```cmd
kubectl patch service pipeline-release-gateway -n data-platform --type=merge -p "{\"spec\":{\"selector\":{\"track\":\"green\"}}}"
```

Kiểm tra selector và EndpointSlice mới:

```cmd
kubectl get service pipeline-release-gateway -n data-platform -o jsonpath="{.spec.selector.track}"
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-release-gateway
```

Gọi lại đúng URL cũ:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-release-gateway:8080/
```

Response bây giờ phải có:

```text
color=green
release=1.0.2
minio_http=200
```

Service name, ClusterIP và port không đổi. Chỉ tập backend endpoints đổi từ hai Pod blue sang hai Pod green.

Xác nhận switch không tạo lại Pod:

```cmd
kubectl get pods -n data-platform -l lab=2.2 -L track,release
kubectl get deployment pipeline-release-blue pipeline-release-green -n data-platform
```

Pod AGE và restart count giữ nguyên.

## Phần 4 — Switch back về blue

Blue/green rollback chỉ cần flip selector ngược lại:

```cmd
kubectl patch service pipeline-release-gateway -n data-platform --type=merge -p "{\"spec\":{\"selector\":{\"track\":\"blue\"}}}"
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-release-gateway:8080/
```

Response trở lại `color=blue`. Không cần `kubectl rollout undo` vì cả hai release vẫn đang chạy.

## Vì sao Service selector flip hoạt động?

Service không gửi traffic trực tiếp đến Deployment. EndpointSlice controller tìm các Pod:

- Khớp toàn bộ selector.
- Có readiness condition đạt yêu cầu.
- Cung cấp named port `http`.

Khi `track` đổi từ `blue` sang `green`, controller cập nhật EndpointSlice. Client vẫn gọi cùng DNS:

```text
pipeline-release-gateway.data-platform.svc
```

## Lệnh CKAD cần nhớ

```cmd
kubectl get svc NAME -o jsonpath="{.spec.selector}"
kubectl patch svc NAME --type=merge -p "{\"spec\":{\"selector\":{\"track\":\"green\"}}}"
kubectl get endpointslice -l kubernetes.io/service-name=NAME
kubectl get pods -l "app=APP,track=green"
```

Selector là phép AND. Service chỉ chọn Pod khớp tất cả labels.

## Batch runner

Chạy deploy và switch blue → green:

```cmd
lab-2.2.bat run
```

Chạy từng phần:

```cmd
lab-2.2.bat deploy
lab-2.2.bat switch-green
lab-2.2.bat switch-blue
lab-2.2.bat verify
lab-2.2.bat cleanup
```

## Cleanup

```cmd
kubectl delete -f .\lab-2.2-blue-green.yaml
```

Cleanup chỉ xóa ConfigMap, hai Deployment, Service và các Pod Lab 2.2. Stack data platform và dữ liệu không bị thay đổi.
