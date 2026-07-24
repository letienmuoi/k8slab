# Lab 4.4: Persistent Volume Claims với pipeline snapshot thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Services and Networking / Application Design and Build.

## Mục tiêu

- Request PVC `1Gi` bằng dynamic provisioning.
- Mount PVC vào Pod.
- Ghi dữ liệu nghiệp vụ thật.
- Xóa Pod nhưng giữ PVC.
- Tạo lại Pod và chứng minh file/checksum không đổi.

## StorageClass local

Kiểm tra:

```cmd
kubectl get storageclass
```

Cluster có default StorageClass:

```text
standard   rancher.io/local-path   WaitForFirstConsumer
```

PVC khai báo rõ `storageClassName: standard`. Provisioner sẽ tạo PV động khi Pod consumer được schedule.

`WaitForFirstConsumer` có nghĩa PVC có thể ở `Pending` sau khi tạo riêng; khi Pod sử dụng PVC được tạo, scheduler chọn node rồi provision/bind volume.

## Dữ liệu được lưu

Pod `pipeline-pvc-auditor` ghi một lần vào:

```text
/var/lib/pipeline-state/dependency-audit.log
```

File chứa:

- thời điểm tạo đầu tiên;
- tên Pod tạo dữ liệu;
- SHA-256 của pipeline JAR;
- Flink jobs response;
- Iceberg Medallion tables;
- MinIO readiness HTTP status.

Nếu file đã tồn tại khi Pod start lại, container không overwrite mà log `event=persistent_state_reused`.

## Phần 0 — Validate

```cmd
kubectl apply --dry-run=client -f .\lab-4.4-pvc.yaml
kubectl apply --dry-run=server -f .\lab-4.4-pvc.yaml
kubectl apply --dry-run=client -f .\lab-4.4-pvc-pod.yaml
```

Server-side dry-run Pod có thể thực hiện sau khi PVC tồn tại.

## Phần 1 — Provision PVC

```cmd
kubectl apply -f .\lab-4.4-pvc.yaml
kubectl get pvc pipeline-audit-state -n data-platform
```

Nếu PVC đang `Pending`, đây là hành vi bình thường của `WaitForFirstConsumer`.

Tạo Pod:

```cmd
kubectl apply --dry-run=server -f .\lab-4.4-pvc-pod.yaml
kubectl apply -f .\lab-4.4-pvc-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-pvc-auditor --timeout=120s
kubectl wait -n data-platform --for=jsonpath="{.status.phase}"=Bound pvc/pipeline-audit-state --timeout=120s
```

Kiểm tra dynamic PV:

```cmd
kubectl get pvc pipeline-audit-state -n data-platform -o wide
kubectl get pv
kubectl describe pvc pipeline-audit-state -n data-platform
```

Expected capacity là `1Gi`, access mode `RWO`, StorageClass `standard`.

## Phần 2 — Kiểm tra dữ liệu lần đầu

```cmd
kubectl logs pipeline-pvc-auditor -n data-platform
kubectl exec pipeline-pvc-auditor -n data-platform -- cat /var/lib/pipeline-state/dependency-audit.log
kubectl exec pipeline-pvc-auditor -n data-platform -- sha256sum /var/lib/pipeline-state/dependency-audit.log
```

Log đầu tiên phải có:

```text
event=persistent_state_created
event=persistent_state_ready
```

Ghi lại checksum.

## Phần 3 — Xóa Pod, giữ PVC

```cmd
kubectl delete pod pipeline-pvc-auditor -n data-platform --wait=true
kubectl get pvc pipeline-audit-state -n data-platform
```

PVC vẫn phải `Bound`. Chỉ xóa Pod không xóa volume hay dữ liệu.

## Phần 4 — Tạo lại và verify persistence

```cmd
kubectl apply -f .\lab-4.4-pvc-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-pvc-auditor --timeout=120s
kubectl logs pipeline-pvc-auditor -n data-platform
kubectl exec pipeline-pvc-auditor -n data-platform -- sha256sum /var/lib/pipeline-state/dependency-audit.log
```

Expected:

```text
event=persistent_state_reused
checksum sau = checksum trước
creator_pod và created_at vẫn là giá trị lần đầu
```

Pod name giống nhau vì cùng manifest, nhưng Pod UID mới:

```cmd
kubectl get pod pipeline-pvc-auditor -n data-platform -o jsonpath="{.metadata.uid}"
```

## PVC, PV và Pod lifecycle

- Pod mount PVC; Pod không sở hữu lifetime của PVC.
- PVC bind tới PV do provisioner tạo.
- Xóa Pod: PVC/PV còn.
- Xóa PVC: StorageClass `reclaimPolicy=Delete` khiến provisioner xóa PV và backing directory.

## Batch runner

```cmd
lab-4.4.bat run
lab-4.4.bat provision
lab-4.4.bat recreate
lab-4.4.bat verify
lab-4.4.bat cleanup
```

## Cleanup

```cmd
kubectl delete -f .\lab-4.4-pvc-pod.yaml --ignore-not-found
kubectl delete -f .\lab-4.4-pvc.yaml --ignore-not-found
```

Cleanup PVC sẽ xóa dữ liệu Lab 4.4; không ảnh hưởng Kafka/Iceberg/MinIO volumes của project.
