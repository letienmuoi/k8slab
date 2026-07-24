# Lab 5.4 — Helm Deploy & Rollback

Thời lượng: khoảng 45 phút
CKAD domain: Application Deployment

## Mục tiêu

- Lint và render Helm chart.
- Install release với value overrides từ CLI.
- Upgrade bằng values file.
- Đọc release history và rollback về revision cũ.

## Prerequisite Helm

Helm được cài tại:

```text
%LOCALAPPDATA%\Programs\Helm\helm.exe
```

Thư mục này đã được thêm vào User `PATH`. Mở cửa sổ `cmd` mới:

```cmd
helm version
helm list -A
```

Runner cũng tự fallback tới đường dẫn trên nếu terminal hiện tại chưa nhận
PATH mới.

## Nghiệp vụ chart

Chart `lab-5.4-chart` deploy `pipeline-helm-auditor` bằng image
`mualanhlung017/ai-data-pipeline:1.0.2`.

Mỗi replica:

- Tính SHA-256 của project JAR.
- Đọc Flink `/jobs/overview`.
- Đọc danh sách bảng medallion từ Iceberg REST.
- Kiểm tra MinIO readiness.
- Log release name, Helm revision, track và kết quả dependency audit.

Đây là workload thật; Helm chỉ thay đổi cấu hình triển khai.

## Chart structure

```text
lab-5.4-chart/
|-- Chart.yaml
|-- values.yaml
|-- values.schema.json
|-- .helmignore
`-- templates/
    |-- _helpers.tpl
    |-- deployment.yaml
    `-- NOTES.txt
```

## Lint và render

```cmd
helm lint .\lab-5.4-chart
helm template pipeline-helm .\lab-5.4-chart -n data-platform --set-string image.tag=1.0.2
```

## Install revision 1

```cmd
helm install pipeline-helm .\lab-5.4-chart -n data-platform --set-string image.tag=1.0.2 --set replicaCount=1 --set releaseTrack=stable --wait --timeout 3m
helm status pipeline-helm -n data-platform
helm history pipeline-helm -n data-platform
```

Expected:

- Helm revision: `1`
- Replicas: `1`
- Track: `stable`
- Audit interval: `15`

## Upgrade revision 2

File `lab-5.4-upgrade-values.yaml` override:

```yaml
replicaCount: 2
releaseTrack: canary
auditIntervalSeconds: 5
```

Upgrade:

```cmd
helm upgrade pipeline-helm .\lab-5.4-chart -n data-platform -f .\lab-5.4-upgrade-values.yaml --set-string image.tag=1.0.2 --wait --timeout 3m
kubectl get deployment pipeline-helm-auditor -n data-platform
helm history pipeline-helm -n data-platform
```

## Rollback

```cmd
helm rollback pipeline-helm 1 -n data-platform --wait --timeout 3m
helm history pipeline-helm -n data-platform
```

Rollback tạo release revision mới `3`; nó không xóa revision 2. Nội dung
manifest của revision 3 được khôi phục nguyên từ revision 1:

- Replicas: `1`
- Track: `stable`
- Audit interval: `15`

Vì manifest cũ được phục hồi nguyên trạng, env `HELM_MANIFEST_REVISION` trong
Pod có giá trị `1`; còn Helm history và Secret release hiện hành có revision
`3`. Hai con số này mô tả hai thứ khác nhau.

Kiểm tra log nghiệp vụ:

```cmd
kubectl logs -n data-platform deployment/pipeline-helm-auditor -c auditor --tail=20
```

## Batch runner

```cmd
lab-5.4.bat run
lab-5.4.bat lint
lab-5.4.bat install
lab-5.4.bat upgrade
lab-5.4.bat rollback
lab-5.4.bat history
lab-5.4.bat verify
lab-5.4.bat cleanup
```

`run` yêu cầu chính xác ba state:

| Release revision | Manifest revision | Replicas | Track | Interval |
|---:|---:|---:|---|---:|
| 1 | 1 | 1 | stable | 15s |
| 2 | 2 | 2 | canary | 5s |
| 3 | 1 | 1 | stable | 15s |

## Cleanup

```cmd
lab-5.4.bat cleanup
```

Cleanup dùng `helm uninstall`; nó không tác động các Deployment pipeline gốc.
