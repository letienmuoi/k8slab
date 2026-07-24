# Lab 2.4: Kustomize Overlay với pipeline thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Deployment.

## Mục tiêu

- Tổ chức manifest theo `base` và `overlays`.
- Dùng lại đúng một Deployment base cho nhiều môi trường.
- Thay image tag và replica count mà không copy Deployment YAML.
- Render, diff, apply và verify bằng `kubectl kustomize`/`kubectl apply -k`.

## Cấu trúc thư mục

```text
lab-2.4/
|-- base/
|   |-- deployment.yaml
|   `-- kustomization.yaml
`-- overlays/
    |-- dev/
    |   `-- kustomization.yaml
    `-- prod/
        `-- kustomization.yaml
```

Chỉ `base/deployment.yaml` định nghĩa Deployment. Hai overlay không copy Pod template, probes, environment variables hoặc resources.

## Nghiệp vụ của workload

`pipeline-kustomize-auditor` sử dụng image thật của project. Mỗi replica:

```text
kiểm tra /opt/flink/usrlib/ai-data-pipeline.jar
  -> lấy SHA-256 của JAR
  -> gọi Flink /jobs/overview
  -> gọi Iceberg namespace medallion/tables
  -> gọi MinIO /minio/health/ready
  -> ghi kết quả thật ra container log
```

Readiness probe cũng gọi ba dependency. Pod chỉ `Ready` khi JAR tồn tại và Flink, Iceberg, MinIO đều truy cập được.

## Base và overlay khác nhau ở đâu?

Base chứa toàn bộ Deployment dùng chung. Overlay dev chỉ khai báo:

```yaml
images:
  - name: mualanhlung017/ai-data-pipeline
    newTag: 1.0.1
replicas:
  - name: pipeline-kustomize-auditor
    count: 1
```

Overlay prod dùng cùng base nhưng thay hai giá trị:

```yaml
images:
  - name: mualanhlung017/ai-data-pipeline
    newTag: 1.0.2
replicas:
  - name: pipeline-kustomize-auditor
    count: 3
```

`nameSuffix` tạo tên `pipeline-kustomize-auditor-dev` và `pipeline-kustomize-auditor-prod`, giúp chạy hai kết quả song song trên cluster local để so sánh. Label transformer thêm `environment=dev|prod` vào cả selector và Pod template.

## Phần 0 — Precheck

```cmd
kubectl get deployment flink-jobmanager flink-taskmanager iceberg-rest minio -n data-platform
kubectl version --client
```

Client local hiện có sẵn lệnh `kubectl kustomize`; không cần cài binary riêng.

## Phần 1 — Render, chưa thay đổi cluster

Render dev:

```cmd
kubectl kustomize .\lab-2.4\overlays\dev
```

Render prod:

```cmd
kubectl kustomize .\lab-2.4\overlays\prod
```

Render là thao tác client-side. Nó chỉ tạo YAML cuối cùng trên stdout, chưa tạo resource.

Kiểm tra nhanh các trường đã transform:

```cmd
kubectl kustomize .\lab-2.4\overlays\dev | findstr /C:"name: pipeline-kustomize-auditor-dev" /C:"replicas:" /C:"image:"
kubectl kustomize .\lab-2.4\overlays\prod | findstr /C:"name: pipeline-kustomize-auditor-prod" /C:"replicas:" /C:"image:"
```

Kết quả chính:

| Overlay | Deployment | Image | Replicas |
|---|---|---|---:|
| dev | `pipeline-kustomize-auditor-dev` | `1.0.1` | 1 |
| prod | `pipeline-kustomize-auditor-prod` | `1.0.2` | 3 |

Có thể validate kết quả render bằng API server mà vẫn không tạo resource:

```cmd
kubectl kustomize .\lab-2.4\overlays\dev | kubectl apply --dry-run=server -f -
kubectl kustomize .\lab-2.4\overlays\prod | kubectl apply --dry-run=server -f -
```

## Phần 2 — Apply dev

Với Kustomize, dùng `-k` trỏ tới thư mục, không dùng `-f` trỏ vào `kustomization.yaml`:

```cmd
kubectl apply -k .\lab-2.4\overlays\dev
kubectl rollout status deployment/pipeline-kustomize-auditor-dev -n data-platform --timeout=120s
```

Verify:

```cmd
kubectl get deployment pipeline-kustomize-auditor-dev -n data-platform
kubectl get deployment pipeline-kustomize-auditor-dev -n data-platform -o jsonpath="{.spec.replicas}"
kubectl get deployment pipeline-kustomize-auditor-dev -n data-platform -o jsonpath="{.spec.template.spec.containers[0].image}"
kubectl get pods -n data-platform -l "lab=2.4,environment=dev"
kubectl logs -n data-platform -l "lab=2.4,environment=dev" --prefix=true --tail=8
```

Expected:

```text
replicas = 1
image    = mualanhlung017/ai-data-pipeline:1.0.1
```

Log phải có `event=dependency_audit`, `minio_http=200`, Flink jobs và các bảng Iceberg Medallion.

## Phần 3 — Apply prod từ cùng base

```cmd
kubectl apply -k .\lab-2.4\overlays\prod
kubectl rollout status deployment/pipeline-kustomize-auditor-prod -n data-platform --timeout=120s
```

Verify:

```cmd
kubectl get deployment pipeline-kustomize-auditor-prod -n data-platform
kubectl get deployment pipeline-kustomize-auditor-prod -n data-platform -o jsonpath="{.spec.replicas}"
kubectl get deployment pipeline-kustomize-auditor-prod -n data-platform -o jsonpath="{.spec.template.spec.containers[0].image}"
kubectl get pods -n data-platform -l "lab=2.4,environment=prod"
kubectl logs -n data-platform -l "lab=2.4,environment=prod" --prefix=true --tail=8 --max-log-requests=4
```

Expected:

```text
replicas = 3
image    = mualanhlung017/ai-data-pipeline:1.0.2
```

## Phần 4 — Diff trước khi apply

Khi resource đã tồn tại, xem thay đổi mà không apply:

```cmd
kubectl diff -k .\lab-2.4\overlays\prod
```

Lưu ý: `kubectl diff` trả exit code `1` khi tìm thấy khác biệt. Đây là “có diff”, không phải lỗi kết nối cluster.

## Lệnh CKAD cần nhớ

```cmd
kubectl kustomize DIRECTORY
kubectl apply -k DIRECTORY
kubectl diff -k DIRECTORY
kubectl delete -k DIRECTORY
```

Phân biệt:

- `kubectl kustomize`: chỉ render YAML.
- `kubectl apply -k`: render rồi apply.
- `kubectl apply -f`: đọc manifest thường; không phải lệnh đúng để build một overlay.

## Batch runner

Chạy toàn bộ:

```cmd
lab-2.4.bat run
```

Chạy từng phần:

```cmd
lab-2.4.bat render
lab-2.4.bat dev
lab-2.4.bat prod
lab-2.4.bat verify
lab-2.4.bat cleanup
```

## Cleanup

```cmd
kubectl delete -k .\lab-2.4\overlays\dev --ignore-not-found
kubectl delete -k .\lab-2.4\overlays\prod --ignore-not-found
```

Cleanup chỉ xóa hai Deployment của Lab 2.4, không thay đổi Flink, Kafka, Iceberg, MinIO hoặc dữ liệu pipeline.
