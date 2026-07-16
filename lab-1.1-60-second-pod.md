# Lab 1.1: The 60-Second Pod với nghiệp vụ thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Design and Build.

## Mục tiêu

- Tạo Pod imperatively bằng `kubectl run`.
- Gắn labels, annotation, environment variables và resource requests/limits.
- Export manifest bằng `--dry-run=client -o yaml`.
- Kiểm tra nhanh Pod bằng `get`, `jsonpath`, `logs`, `describe` mà không mở editor.
- Chạy một operational monitor thật trong đúng khoảng 60 giây.

## Nghiệp vụ của Pod

Pod dùng image thật của project:

```text
mualanhlung017/ai-data-pipeline:1.0.2
```

Trong 60 giây, Pod query Flink REST endpoint `/jobs/overview` mỗi 10 giây. Log là JSON trạng thái thật của `MedallionPipelineJob`, gồm job ID, tên pipeline, state `RUNNING`, duration và task counts.

```text
pod-60
  -> curl http://flink-jobmanager:8081/jobs/overview
  -> chờ CHECK_INTERVAL_SECONDS
  -> lặp đến MONITOR_DURATION_SECONDS
  -> exit 0 / Pod Completed
```

`sleep` chỉ là khoảng nghỉ giữa hai lần health query; workload không tạo stage hoặc log giả.

## Phần 0 — Kiểm tra Flink thật

```cmd
kubectl get deployment flink-jobmanager flink-taskmanager -n data-platform
```

Cả hai Deployment phải `READY 1/1`. Nếu Flink REST không truy cập được, `curl -f` làm Pod thoát lỗi thay vì báo thành công giả.

## Phần 1 — Export manifest bằng dry-run

Chạy nguyên một dòng sau trong Windows `cmd`:

```cmd
kubectl run pod-60 --namespace=data-platform --image=mualanhlung017/ai-data-pipeline:1.0.2 --image-pull-policy=IfNotPresent --restart=Never --labels=app=ai-data-pipeline,lab=1.1,component=flink-monitor --annotations=lab.muoilt.vn/purpose=monitor-flink-for-60-seconds --env=APP_ENV=lab --env=OWNER=franc --env=CHECK_TARGET=http://flink-jobmanager:8081/jobs/overview --env=CHECK_INTERVAL_SECONDS=10 --env=MONITOR_DURATION_SECONDS=60 --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"pod-60\",\"resources\":{\"requests\":{\"cpu\":\"25m\",\"memory\":\"32Mi\"},\"limits\":{\"cpu\":\"100m\",\"memory\":\"128Mi\"}}}]}}" --override-type=strategic --dry-run=client -o yaml --command -- /usr/bin/bash -ec "deadline=$((SECONDS + MONITOR_DURATION_SECONDS)); while (( SECONDS < deadline )); do /usr/bin/curl -fsS \"$CHECK_TARGET\"; printf \"\\n\"; /usr/bin/sleep \"$CHECK_INTERVAL_SECONDS\"; done" > pod-60.yaml
```

Điểm quan trọng:

- `--dry-run=client -o yaml` phải đứng trước `--command --`. Mọi token sau `--` được coi là command/argument của container.
- `--override-type=strategic` cho phép merge `resources` vào container mà vẫn giữ image, command và env do `kubectl run` sinh ra.
- Lệnh này chỉ ghi file; nó chưa tạo Pod.

Kiểm tra file mà không mở editor:

```cmd
type pod-60.yaml
kubectl create --dry-run=client -f .\pod-60.yaml
```

## Phần 2 — Tạo Pod

```cmd
kubectl create -f .\pod-60.yaml
kubectl get pod pod-60 -n data-platform --show-labels
```

Ngay khi Pod đang chạy:

```cmd
kubectl get pod pod-60 -n data-platform -o wide
kubectl logs pod-60 -n data-platform --tail=2
```

Mỗi log line là response thật từ Flink, ví dụ chứa:

```json
{"jobs":[{"name":"insert-into_lakehouse.medallion...","state":"RUNNING","tasks":{"running":4,...}}]}
```

## Phần 3 — Exam speed verification, không mở editor

Labels:

```cmd
kubectl get pod pod-60 -n data-platform -o jsonpath="{.metadata.labels}"
```

Environment variables:

```cmd
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].env}"
```

Requests và limits:

```cmd
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].resources}"
```

Image, restart policy và command:

```cmd
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].image}"
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.restartPolicy}"
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].command}"
```

Tổng hợp nhanh bằng label columns và describe:

```cmd
kubectl get pod pod-60 -n data-platform -L app,lab,component
kubectl describe pod pod-60 -n data-platform
```

Giá trị cần thấy:

- Labels: `app=ai-data-pipeline`, `lab=1.1`, `component=flink-monitor`.
- Env: `APP_ENV`, `OWNER`, `CHECK_TARGET`, `CHECK_INTERVAL_SECONDS`, `MONITOR_DURATION_SECONDS`.
- Requests: `cpu=25m`, `memory=32Mi`.
- Limits: `cpu=100m`, `memory=128Mi`.
- `restartPolicy=Never`.

## Phần 4 — Quan sát lifecycle 60 giây

Chờ Pod kết thúc thành công:

```cmd
kubectl wait -n data-platform --for=jsonpath="{.status.phase}"=Succeeded pod/pod-60 --timeout=90s
kubectl get pod pod-60 -n data-platform
kubectl logs pod-60 -n data-platform
```

Kết quả mong đợi:

- Trong khoảng 60 giây đầu: `Running`.
- Sau đó: `Completed`, exit code `0`.
- Log có khoảng sáu snapshot JSON của Flink REST.

Kiểm tra exit code không cần `describe`:

```cmd
kubectl get pod pod-60 -n data-platform -o jsonpath="{.status.containerStatuses[0].state.terminated.exitCode}"
```

## Làm lại và cleanup

Pod đã `Completed` không thể chạy lại bằng `kubectl create` cùng tên. Xoá rồi tạo lại:

```cmd
kubectl delete pod pod-60 -n data-platform
kubectl create -f .\pod-60.yaml
```

Kết thúc lab:

```cmd
kubectl delete pod pod-60 -n data-platform --ignore-not-found
```

