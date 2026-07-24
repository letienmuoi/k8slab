# Lab 3.2: Security Context Lockdown với project image

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Environment, Configuration & Security.

## Mục tiêu

- Chạy Pod bằng UID/GID không phải root.
- Đặt root filesystem thành read-only.
- Drop toàn bộ Linux capabilities.
- Không cho phép privilege escalation.
- Vẫn chạy được workload nghiệp vụ với một writable volume tối thiểu.

## Nghiệp vụ

Pod `pipeline-secure-auditor` dùng image project `1.0.2` để:

- kiểm tra pipeline JAR thật;
- gọi Flink jobs;
- đọc danh sách Iceberg Medallion tables;
- kiểm tra MinIO readiness.

Pod không cần root, Linux capabilities hoặc Kubernetes API token để làm các việc này.

## SecurityContext

Pod-level:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
```

Container-level:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

`automountServiceAccountToken: false` loại bỏ token không cần thiết.

Root filesystem chỉ đọc không có nghĩa ứng dụng không bao giờ được ghi. Pod mount một `emptyDir` giới hạn `16Mi` tại `/tmp`; đây là vùng writable rõ ràng và có vòng đời bằng Pod.

## Phần 0 — Validate

```cmd
kubectl apply --dry-run=client -f .\lab-3.2-security-context.yaml
kubectl apply --dry-run=server -f .\lab-3.2-security-context.yaml
```

## Phần 1 — Deploy

```cmd
kubectl apply -f .\lab-3.2-security-context.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-secure-auditor --timeout=120s
```

## Phần 2 — Verify manifest nhanh

```cmd
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.securityContext.runAsNonRoot}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.securityContext.runAsUser}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.containers[0].securityContext.readOnlyRootFilesystem}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.containers[0].securityContext.allowPrivilegeEscalation}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.containers[0].securityContext.capabilities.drop[0]}"
```

Expected:

```text
true
10001
true
false
ALL
```

## Phần 3 — Verify runtime

UID/GID thực tế:

```cmd
kubectl exec pipeline-secure-auditor -n data-platform -- id
```

Expected có `uid=10001` và `gid=10001`.

Root filesystem phải từ chối ghi:

```cmd
kubectl exec pipeline-secure-auditor -n data-platform -- touch /rootfs-write-test
```

Lệnh này phải thất bại với `Read-only file system`.

Writable volume vẫn hoạt động:

```cmd
kubectl exec pipeline-secure-auditor -n data-platform -- touch /tmp/secure-write-test
kubectl exec pipeline-secure-auditor -n data-platform -- ls -l /tmp/secure-write-test
kubectl exec pipeline-secure-auditor -n data-platform -- rm /tmp/secure-write-test
```

Xem log nghiệp vụ:

```cmd
kubectl logs pipeline-secure-auditor -n data-platform --tail=10
```

Log phải có UID `10001`, `minio_http=200`, response Flink và các bảng Iceberg.

## Phân biệt Pod-level và container-level

- `runAsUser`, `runAsGroup`, `fsGroup`, `seccompProfile` thường đặt ở Pod level để chia sẻ mặc định cho containers.
- `capabilities`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation` là container security context.
- Container có thể override một số giá trị Pod-level nếu manifest cho phép.

## Batch runner

```cmd
lab-3.2.bat run
lab-3.2.bat apply
lab-3.2.bat verify
lab-3.2.bat cleanup
```

## Cleanup

```cmd
kubectl delete -f .\lab-3.2-security-context.yaml --ignore-not-found
```

Pod lab độc lập, không thay đổi securityContext của Flink, Kafka, Iceberg hoặc MinIO.
