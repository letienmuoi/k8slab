# Lab 3.1: ConfigMap & Secret Injection với pipeline thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Environment, Configuration & Security.

## Mục tiêu

- Tạo Secret từ file bằng `kubectl create secret --from-file`.
- Tạo ConfigMap từ các literal bằng `kubectl create configmap --from-literal`.
- Inject một Secret key thành environment variable.
- Mount ConfigMap thành volume trong cùng một Pod.
- Kiểm tra workload dùng cấu hình để gọi dependency thật.

## Nghiệp vụ

Pod `pipeline-config-auditor` chạy image:

```text
mualanhlung017/ai-data-pipeline:1.0.2
```

ConfigMap cung cấp ba endpoint:

```text
flink.jobs.url
iceberg.tables.url
minio.ready.url
```

Mỗi key trở thành một file dưới `/etc/pipeline/endpoints`. Secret `catalog-client.token` được inject vào env `CATALOG_CLIENT_TOKEN` và gửi trong Authorization header khi query Iceberg.

Pod không in token. Log chỉ chứa SHA-256 fingerprint để chứng minh env đã được nạp, cùng response thật từ Flink, Iceberg và MinIO.

File token trong lab là credential không nhạy cảm chỉ dành cho thực hành. Không commit Secret production vào Git.

## Phần 0 — Precheck

```cmd
kubectl get deployment flink-jobmanager iceberg-rest minio -n data-platform
kubectl apply --dry-run=client -f .\lab-3.1-config-secret-pod.yaml
```

## Phần 1 — Tạo Secret từ file

```cmd
kubectl create secret generic pipeline-catalog-secret -n data-platform --from-file=catalog-client.token=.\lab-3.1-files\catalog-client.token.example
kubectl label secret pipeline-catalog-secret -n data-platform app=ai-data-pipeline lab=3.1 component=config-auditor
```

Kiểm tra metadata mà không decode/in giá trị:

```cmd
kubectl get secret pipeline-catalog-secret -n data-platform
kubectl describe secret pipeline-catalog-secret -n data-platform
```

Kết quả phải có key `catalog-client.token`.

## Phần 2 — Tạo ConfigMap từ literal

```cmd
kubectl create configmap pipeline-endpoints -n data-platform --from-literal=flink.jobs.url=http://flink-jobmanager:8081/jobs/overview --from-literal=iceberg.tables.url=http://iceberg-rest:8181/v1/namespaces/medallion/tables --from-literal=minio.ready.url=http://minio:9000/minio/health/ready
kubectl label configmap pipeline-endpoints -n data-platform app=ai-data-pipeline lab=3.1 component=config-auditor
```

Kiểm tra:

```cmd
kubectl get configmap pipeline-endpoints -n data-platform -o yaml
```

ConfigMap không dành cho password/token vì dữ liệu của nó không được bảo vệ như Secret.

## Phần 3 — Inject vào một Pod

Manifest dùng Secret thành env:

```yaml
env:
  - name: CATALOG_CLIENT_TOKEN
    valueFrom:
      secretKeyRef:
        name: pipeline-catalog-secret
        key: catalog-client.token
```

ConfigMap được mount thành directory:

```yaml
volumeMounts:
  - name: endpoints
    mountPath: /etc/pipeline/endpoints
    readOnly: true
volumes:
  - name: endpoints
    configMap:
      name: pipeline-endpoints
```

Apply:

```cmd
kubectl apply -f .\lab-3.1-config-secret-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-config-auditor --timeout=120s
```

## Phần 4 — Verify

Xác nhận source của env và volume mà không mở editor:

```cmd
kubectl get pod pipeline-config-auditor -n data-platform -o jsonpath="{.spec.containers[0].env[0].valueFrom.secretKeyRef.name}"
kubectl get pod pipeline-config-auditor -n data-platform -o jsonpath="{.spec.volumes[0].configMap.name}"
```

Expected:

```text
pipeline-catalog-secret
pipeline-endpoints
```

Xem các file từ ConfigMap:

```cmd
kubectl exec pipeline-config-auditor -n data-platform -- ls -l /etc/pipeline/endpoints
kubectl exec pipeline-config-auditor -n data-platform -- cat /etc/pipeline/endpoints/flink.jobs.url
kubectl exec pipeline-config-auditor -n data-platform -- cat /etc/pipeline/endpoints/iceberg.tables.url
kubectl exec pipeline-config-auditor -n data-platform -- cat /etc/pipeline/endpoints/minio.ready.url
```

Xem log nghiệp vụ:

```cmd
kubectl logs pipeline-config-auditor -n data-platform --tail=10
```

Log phải có:

- `event=config_loaded` và fingerprint, không có token plaintext.
- Flink job state `RUNNING`.
- Iceberg tables `bronze_lines`, `silver_lines`, `gold_ai_ready`.
- `minio_http=200`.

## Exam-speed commands

```cmd
kubectl create secret generic NAME --from-file=KEY=FILE
kubectl create configmap NAME --from-literal=KEY=VALUE
kubectl set env pod/NAME --from=secret/SECRET
kubectl describe pod NAME
```

`kubectl set env` hữu ích cho workload controller; với Pod đang tồn tại, env/volume không thể sửa tùy ý vì nhiều Pod spec field là immutable. Trong bài này ta khai báo injection trong manifest ngay từ đầu.

## Batch runner

```cmd
lab-3.1.bat run
lab-3.1.bat create-config
lab-3.1.bat pod
lab-3.1.bat verify
lab-3.1.bat cleanup
```

## Cleanup

```cmd
kubectl delete pod pipeline-config-auditor -n data-platform --ignore-not-found
kubectl delete configmap pipeline-endpoints -n data-platform --ignore-not-found
kubectl delete secret pipeline-catalog-secret -n data-platform --ignore-not-found
```

Cleanup không thay đổi Secret `minio-credentials` hoặc cấu hình production của project.
