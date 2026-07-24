# Lab 3.4: Namespace Quotas với workload pipeline

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Environment, Configuration & Security.

## Mục tiêu

- Tạo namespace độc lập cho bài quota.
- Áp dụng LimitRange để inject default requests/limits.
- Áp dụng ResourceQuota cho tổng tài nguyên namespace.
- Quan sát API server từ chối Pod làm vượt quota.

## Vì sao dùng namespace riêng?

ResourceQuota áp dụng cho toàn namespace. Đặt quota thử nghiệm trực tiếp vào `data-platform` có thể chặn Flink, Kafka, Iceberg hoặc MinIO khi chúng rollout.

Lab dùng:

```text
pipeline-quota-lab
```

Pod trong namespace này vẫn gọi dependency project qua service FQDN:

```text
flink-jobmanager.data-platform.svc.cluster.local
iceberg-rest.data-platform.svc.cluster.local
minio.data-platform.svc.cluster.local
```

## Chính sách

LimitRange inject vào mỗi container không khai báo resources:

| Trường | CPU | Memory |
|---|---:|---:|
| default request | `100m` | `64Mi` |
| default limit | `200m` | `128Mi` |
| min | `10m` | `16Mi` |
| max | `300m` | `256Mi` |

ResourceQuota:

```yaml
hard:
  pods: "2"
  requests.cpu: 150m
  requests.memory: 192Mi
  limits.cpu: 300m
  limits.memory: 384Mi
```

Pod đầu tiên dùng `100m` request và `200m` limit do LimitRange inject. Pod thứ hai cũng yêu cầu các default đó, làm tổng CPU thành:

```text
requests.cpu: 200m > 150m
limits.cpu:   400m > 300m
```

Do đó Pod thứ hai bị từ chối dù quota `pods=2` chưa đầy.

## Phần 0 — Tạo namespace

```cmd
kubectl apply -f .\lab-3.4-namespace.yaml
kubectl wait --for=jsonpath="{.status.phase}"=Active namespace/pipeline-quota-lab --timeout=60s
```

## Phần 1 — Apply LimitRange và ResourceQuota

```cmd
kubectl apply --dry-run=server -f .\lab-3.4-quota-policy.yaml
kubectl apply -f .\lab-3.4-quota-policy.yaml
kubectl get limitrange,resourcequota -n pipeline-quota-lab
kubectl describe limitrange pipeline-container-defaults -n pipeline-quota-lab
kubectl describe resourcequota pipeline-compute-quota -n pipeline-quota-lab
```

Namespace phải tồn tại trước server-side dry-run của hai resource namespaced.

## Phần 2 — Pod được chấp nhận

Manifest cố ý không có trường `resources`.

```cmd
kubectl apply -f .\lab-3.4-allowed-pod.yaml
kubectl wait -n pipeline-quota-lab --for=condition=Ready pod/quota-auditor-allowed --timeout=120s
```

Kiểm tra resources sau admission:

```cmd
kubectl get pod quota-auditor-allowed -n pipeline-quota-lab -o jsonpath="{.spec.containers[0].resources}"
kubectl describe resourcequota pipeline-compute-quota -n pipeline-quota-lab
kubectl logs quota-auditor-allowed -n pipeline-quota-lab --tail=10
```

Stored Pod spec phải có:

```text
requests: cpu=100m, memory=64Mi
limits:   cpu=200m, memory=128Mi
```

Log phải chứa response thật từ Flink/Iceberg và `minio_http=200`.

## Phần 3 — Pod bị quota từ chối

```cmd
kubectl apply -f .\lab-3.4-overflow-pod.yaml
```

Lệnh phải thất bại. Error quan trọng:

```text
forbidden: exceeded quota: pipeline-compute-quota
```

Kiểm tra:

```cmd
kubectl get pod quota-auditor-overflow -n pipeline-quota-lab
```

Kết quả phải là `NotFound`: admission từ chối trước khi Pod object được lưu, nên không có Pod status hay Pod event để xem.

## Phân biệt LimitRange và ResourceQuota

- LimitRange kiểm soát/default tài nguyên của từng container hoặc Pod.
- ResourceQuota giới hạn tổng tài nguyên đã yêu cầu trong namespace.
- LimitRange có thể inject requests/limits trước; ResourceQuota sau đó tính các giá trị đã inject.
- ResourceQuota không tự chia tài nguyên đều cho Pod.

## Lệnh CKAD cần nhớ

```cmd
kubectl get quota,limitrange -n NAMESPACE
kubectl describe quota NAME -n NAMESPACE
kubectl describe limitrange NAME -n NAMESPACE
kubectl get pod NAME -o jsonpath="{.spec.containers[0].resources}"
```

## Batch runner

```cmd
lab-3.4.bat run
lab-3.4.bat setup
lab-3.4.bat allowed
lab-3.4.bat reject
lab-3.4.bat verify
lab-3.4.bat cleanup
```

## Cleanup

```cmd
kubectl delete namespace pipeline-quota-lab --ignore-not-found
```

Xóa namespace dọn LimitRange, ResourceQuota và Pod của lab; namespace `data-platform` không bị thay đổi.
