# Lab 2.3: Scale & HPA với LineNormalizer thật

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Application Deployment.

## Mục tiêu

- Scale thủ công Deployment từ 2 lên 10 replica.
- Cấu hình HPA `min=2`, `max=10`, target CPU `50%`.
- Hiểu target utilization được tính trên CPU request.
- Quan sát Metrics API, `kubectl top`, HPA conditions và CPU load thật.

## Nghiệp vụ

Deployment `pipeline-normalizer-api` chạy image:

```text
mualanhlung017/ai-data-pipeline:1.0.2
```

API dùng đúng thuật toán từ `LineNormalizer` trong project:

```text
NFKC Unicode -> trim -> gộp whitespace -> lowercase Locale.ROOT
```

Ví dụ:

```text
"  DU   LIEU\tAI  " -> "du lieu ai"
"ＡＢＣ １２３"       -> "abc 123"
```

Endpoint:

- `/normalize?line=...`: normalize một line và trả character count.
- `/work?rounds=50000`: chạy nhiều lần normalization thật để tạo CPU load có kiểm soát.
- `/live` và `/ready`: probe.

Source Java nằm trong ConfigMap, init container JDK compile vào `emptyDir`, còn main container dùng Java runtime và JAR thật của image project.

## Phần 0 — Metrics Server

CPU HPA cần API `metrics.k8s.io`. Kiểm tra:

```cmd
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

Nếu chưa có, cài manifest local:

```cmd
kubectl apply -f .\lab-2.3-metrics-server.yaml
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s
kubectl top nodes
```

Manifest được lấy từ Metrics Server `v0.9.0` chính thức và thêm `--kubelet-insecure-tls` cho Kubernetes local/Docker Desktop. Flag này chỉ phù hợp môi trường lab.

Batch runner tự kiểm tra: nếu Metrics API đã hoạt động thì không cài đè.

## Phần 1 — Deploy normalizer API

```cmd
kubectl apply -f .\lab-2.3-normalizer.yaml
kubectl rollout status deployment/pipeline-normalizer-api -n data-platform --timeout=180s
```

Kiểm tra hai replica ban đầu:

```cmd
kubectl get deployment pipeline-normalizer-api -n data-platform
kubectl get pods -n data-platform -l lab=2.3 -L component
```

Gọi logic thật:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://pipeline-normalizer:8080/normalize?line=%20%20DU%20%20%20LIEU%09AI%20%20"
```

Khi gõ trực tiếp ở prompt `cmd`, dùng `%20` và `%09` như trên. Chỉ bên trong file `.bat` mới phải đổi mỗi `%` thành `%%`.

Kết quả phải chứa:

```text
normalized=du lieu ai
character_count=10
```

## Phần 2 — Manual scale lên 10

Đảm bảo HPA chưa tồn tại để nó không ghi đè manual scale:

```cmd
kubectl delete hpa pipeline-normalizer-api -n data-platform --ignore-not-found
kubectl scale deployment/pipeline-normalizer-api -n data-platform --replicas=10
kubectl rollout status deployment/pipeline-normalizer-api -n data-platform --timeout=180s
kubectl get deployment pipeline-normalizer-api -n data-platform
kubectl get pods -n data-platform -l "lab=2.3,component=normalizer-api"
```

Exam-speed verification:

```cmd
kubectl get deployment pipeline-normalizer-api -n data-platform -o jsonpath="{.spec.replicas}"
kubectl get deployment pipeline-normalizer-api -n data-platform -o jsonpath="{.status.readyReplicas}"
```

Cả hai giá trị phải là `10`.

## Phần 3 — Configure HPA CPU 50%

Cách imperative nhanh:

```cmd
kubectl autoscale deployment pipeline-normalizer-api -n data-platform --min=2 --max=10 --cpu=50%
```

Hoặc dùng manifest `autoscaling/v2`:

```cmd
kubectl apply -f .\lab-2.3-hpa.yaml
kubectl wait -n data-platform --for=condition=ScalingActive hpa/pipeline-normalizer-api --timeout=180s
```

Kiểm tra:

```cmd
kubectl get hpa pipeline-normalizer-api -n data-platform
kubectl describe hpa pipeline-normalizer-api -n data-platform
kubectl get hpa pipeline-normalizer-api -n data-platform -o jsonpath="{.spec.metrics[0].resource.target.averageUtilization}"
```

Target phải là `50`.

Container có:

```yaml
requests:
  cpu: 100m
limits:
  cpu: 150m
```

Vì vậy target `50%` tương ứng trung bình khoảng `50m` CPU trên mỗi Pod. HPA dùng request làm mẫu số, không dùng CPU limit.

CPU limit `150m` giữ workload đủ cao để thấy HPA phản ứng nhưng không chiếm hết CPU của Kubernetes local một node. JVM cũng được giới hạn heap để 10 replica không gây áp lực bộ nhớ không cần thiết.

## Phần 4 — Tạo CPU load thật

Job chạy tám worker, liên tục gọi `/work` trong 90 giây:

```cmd
kubectl delete job pipeline-normalizer-load -n data-platform --ignore-not-found
kubectl apply -f .\lab-2.3-load-job.yaml
```

Quan sát ở cửa sổ khác:

```cmd
kubectl get hpa pipeline-normalizer-api -n data-platform -w
kubectl top pods -n data-platform -l "lab=2.3,component=normalizer-api"
kubectl get deployment pipeline-normalizer-api -n data-platform
```

Chờ Job:

```cmd
kubectl wait -n data-platform --for=condition=complete job/pipeline-normalizer-load --timeout=180s
kubectl logs job/pipeline-normalizer-load -n data-platform
```

Vì manual scale đã đưa Deployment tới `maxReplicas=10`, HPA không thể tăng vượt 10 dù CPU cao. Sau khi load dừng và hết stabilization window, HPA có thể giảm dần về `minReplicas=2`.

## Manual scaling và HPA ai thắng?

Sau khi HPA tồn tại, HPA controller quản lý trường replica thông qua scale subresource. Lệnh:

```cmd
kubectl scale deployment/pipeline-normalizer-api --replicas=5
```

có thể chỉ có hiệu lực tạm thời; vòng reconcile HPA tiếp theo sẽ tính lại desired replicas từ CPU. Muốn luyện manual scale ổn định, xóa/suspend HPA trước.

## Batch runner

Chạy toàn bộ:

```cmd
lab-2.3.bat run
```

Chạy từng phần:

```cmd
lab-2.3.bat deploy
lab-2.3.bat scale10
lab-2.3.bat hpa
lab-2.3.bat load
lab-2.3.bat verify
lab-2.3.bat cleanup
lab-2.3.bat cleanup-metrics
```

`cleanup` giữ Metrics Server vì đây là cluster add-on dùng chung. `cleanup-metrics` chỉ xóa nó nếu Deployment có annotation xác nhận được cài bởi Lab 2.3.

## Cleanup

```cmd
kubectl delete -f .\lab-2.3-load-job.yaml --ignore-not-found
kubectl delete -f .\lab-2.3-hpa.yaml --ignore-not-found
kubectl delete -f .\lab-2.3-normalizer.yaml --ignore-not-found
```

Không ảnh hưởng Kafka, Flink, Iceberg, MinIO hoặc dữ liệu pipeline.
