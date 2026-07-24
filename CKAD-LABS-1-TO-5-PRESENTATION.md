# Kịch bản trình bày CKAD Labs 1.1–5.4

Tài liệu này là speaker guide để trình bày toàn bộ 20 bài lab trên Windows
`cmd`. Các workload không in kết quả giả: chúng dùng image
`mualanhlung017/ai-data-pipeline:1.0.2` và tương tác với Kafka, Flink, Iceberg
REST, MinIO hoặc Kubernetes API thật của project.

> Khi trình bày, chạy lệnh trong từng khối theo thứ tự. Những lệnh được ghi
> **expected failure** phải thất bại; đó là một phần của bài học, không phải lỗi
> của buổi demo.

Mở nhanh trong VS Code:

```cmd
code .\CKAD-LABS-1-TO-5-PRESENTATION.md
```

Dùng `Ctrl+Shift+V` để mở Markdown Preview. Bảng “Bản đồ 20 bài lab” bên dưới
cho phép click để nhảy thẳng tới từng bài.

## 0. Chuẩn bị trước giờ trình bày

### 0.1. Mở đúng terminal và thư mục

Mở một cửa sổ `cmd` mới, rồi chạy:

```cmd
cd /d C:\Users\franc\source\muoilt_k8slab
chcp 65001
```

Tài liệu này dùng cú pháp của `cmd`:

- Biến vòng lặp tương tác là `%P`, không phải `%%P`.
- URL encode dùng `%20`; chỉ trong file `.bat` mới phải viết `%%20`.
- JSON patch được escape bằng `\"`.
- Có thể paste từng khối lệnh trực tiếp từ tài liệu.

### 0.2. Kiểm tra công cụ và cluster

```cmd
where kubectl
kubectl version --client
kubectl config current-context
kubectl get nodes -o wide
kubectl get namespace data-platform
helm version
```

Helm đã được cài tại:

```text
%LOCALAPPDATA%\Programs\Helm\helm.exe
```

Nếu terminal cũ chưa nhận `PATH`, đóng nó và mở `cmd` mới.

### 0.3. Kiểm tra data platform gốc

```cmd
kubectl get deployment -n data-platform
kubectl get pods -n data-platform
kubectl get service -n data-platform
kubectl get storageclass
```

Các Deployment nền cần sẵn sàng:

```text
kafka
flink-jobmanager
flink-taskmanager
iceberg-rest
minio
nifi
```

Nếu stack chưa tồn tại, triển khai từ project gốc:

```cmd
cd /d C:\Users\franc\source\muoilt_k8sproj
kubectl apply -k .
kubectl rollout status deployment/kafka -n data-platform --timeout=180s
kubectl rollout status deployment/flink-jobmanager -n data-platform --timeout=300s
kubectl rollout status deployment/flink-taskmanager -n data-platform --timeout=300s
cd /d C:\Users\franc\source\muoilt_k8slab
```

### 0.4. Câu chuyện nghiệp vụ xuyên suốt

```text
NiFi/Kafka raw-data
        |
        v
Flink MedallionPipelineJob + LineNormalizer
        |
        +--> Kafka refined-data
        |
        +--> Iceberg Bronze / Silver / Gold trên MinIO
```

Các lab không thay thế pipeline trên. Mỗi bài lấy một phần nghiệp vụ thật để
luyện đúng Kubernetes primitive:

- Day 1: cách xây Pod và tác vụ hữu hạn.
- Day 2: cách phát hành, chuyển traffic và scale ứng dụng.
- Day 3: cách đưa cấu hình vào workload và khóa quyền.
- Day 4: cách kết nối, cô lập và lưu dữ liệu.
- Day 5: cách tự chữa lỗi, quan sát, chẩn đoán và quản lý release.

### 0.5. Hai cách demo

Mỗi lab có hai đường chạy:

1. **Demo nhanh:** `lab-X.Y.bat run` tự kiểm tra đầy đủ và dừng nếu sai.
2. **Demo giải thích:** chạy các lệnh thủ công trong mục tương ứng để cả lớp
   nhìn thấy từng trạng thái.

Nếu một demo thủ công bị dang dở:

```cmd
lab-X.Y.bat cleanup
lab-X.Y.bat run
```

Không chạy cleanup bằng selector quá rộng như `--all`. Runner chỉ xóa resource
thuộc đúng lab.

## Bản đồ 20 bài lab

| Lab | Trọng tâm | Lệnh demo nhanh |
|---|---|---|
| [1.1](#lab-1-1) | Imperative Pod và dry-run | `lab-1.1.bat run` |
| [1.2](#lab-1-2) | Init container, app, sidecar, `emptyDir` | `lab-1.2.bat run` |
| [1.3](#lab-1-3) | Job và CronJob | `lab-1.3.bat run` |
| [1.4](#lab-1-4) | Label, selector và annotation | `lab-1.4.bat run` |
| [2.1](#lab-2-1) | Rolling update và rollback | `lab-2.1.bat run` |
| [2.2](#lab-2-2) | Blue/green bằng Service selector | `lab-2.2.bat run` |
| [2.3](#lab-2-3) | Manual scale và HPA | `lab-2.3.bat run` |
| [2.4](#lab-2-4) | Kustomize base/overlay | `lab-2.4.bat run` |
| [3.1](#lab-3-1) | ConfigMap và Secret injection | `lab-3.1.bat run` |
| [3.2](#lab-3-2) | SecurityContext lockdown | `lab-3.2.bat run` |
| [3.3](#lab-3-3) | ServiceAccount và RBAC | `lab-3.3.bat run` |
| [3.4](#lab-3-4) | ResourceQuota và LimitRange | `lab-3.4.bat run` |
| [4.1](#lab-4-1) | ClusterIP, NodePort và selector lỗi | `lab-4.1.bat run` |
| [4.2](#lab-4-2) | Ingress path routing | `lab-4.2.bat run` |
| [4.3](#lab-4-3) | NetworkPolicy isolation | `lab-4.3.bat run` |
| [4.4](#lab-4-4) | PVC và dữ liệu bền vững | `lab-4.4.bat run` |
| [5.1](#lab-5-1) | Startup, readiness và liveness | `lab-5.1.bat run` |
| [5.2](#lab-5-2) | Logs, Events và Metrics | `lab-5.2.bat run` |
| [5.3](#lab-5-3) | Broken YAML triage | `lab-5.3.bat run` |
| [5.4](#lab-5-4) | Helm install, upgrade và rollback | `lab-5.4.bat run` |

---

# Day 1 — Application Design and Build

<a id="lab-1-1"></a>

## Lab 1.1 — The 60-Second Pod

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** tạo Pod bằng lệnh imperative, thêm labels, env, resource
requests/limits, export YAML bằng client dry-run và kiểm tra nhanh không mở
editor.

### Điều cần trình bày

Pod `pod-60` chạy image project và gọi Flink
`/jobs/overview` mỗi 10 giây trong 60 giây. Đây là một monitor hữu hạn, nên trạng
thái cuối `Completed` là đúng.

`--dry-run=client -o yaml` chỉ sinh manifest; nó **không tạo Pod trên cluster**.

### Demo nhanh

```cmd
lab-1.1.bat run
```

### Demo thủ công

Xóa Pod cũ, rồi sinh manifest imperative:

```cmd
kubectl delete pod pod-60 -n data-platform --ignore-not-found
kubectl run pod-60 --namespace=data-platform --image=mualanhlung017/ai-data-pipeline:1.0.2 --image-pull-policy=IfNotPresent --restart=Never --labels=app=ai-data-pipeline,lab=1.1,component=flink-monitor --annotations=lab.muoilt.vn/purpose=monitor-flink-for-60-seconds --env=APP_ENV=lab --env=OWNER=franc --env=CHECK_TARGET=http://flink-jobmanager:8081/jobs/overview --env=CHECK_INTERVAL_SECONDS=10 --env=MONITOR_DURATION_SECONDS=60 --overrides="{\"apiVersion\":\"v1\",\"spec\":{\"containers\":[{\"name\":\"pod-60\",\"resources\":{\"requests\":{\"cpu\":\"25m\",\"memory\":\"32Mi\"},\"limits\":{\"cpu\":\"100m\",\"memory\":\"128Mi\"}}}]}}" --override-type=strategic --dry-run=client -o yaml --command -- /usr/bin/bash -ec "deadline=$((SECONDS + MONITOR_DURATION_SECONDS)); while (( SECONDS < deadline )); do /usr/bin/curl -fsS \"$CHECK_TARGET\"; printf \"\\n\"; /usr/bin/sleep \"$CHECK_INTERVAL_SECONDS\"; done" > pod-60.generated.yaml
```

Chứng minh file đã được tạo nhưng Pod chưa tồn tại:

```cmd
type pod-60.generated.yaml
kubectl get pod pod-60 -n data-platform
```

Lệnh `get` trên phải báo `NotFound`. Validate rồi tạo Pod:

```cmd
kubectl create --dry-run=client -f .\pod-60.generated.yaml
kubectl create -f .\pod-60.generated.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pod-60 --timeout=60s
```

Exam-speed verification:

```cmd
kubectl get pod pod-60 -n data-platform --show-labels
kubectl get pod pod-60 -n data-platform -o jsonpath="{.metadata.labels}"
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].env}"
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.containers[0].resources}"
kubectl get pod pod-60 -n data-platform -o jsonpath="{.spec.restartPolicy}"
```

Chờ monitor kết thúc và đọc kết quả:

```cmd
kubectl wait -n data-platform --for=jsonpath="{.status.phase}"=Succeeded pod/pod-60 --timeout=90s
kubectl get pod pod-60 -n data-platform
kubectl logs pod-60 -n data-platform
kubectl get pod pod-60 -n data-platform -o custom-columns="REASON:.status.containerStatuses[0].state.terminated.reason,EXIT_CODE:.status.containerStatuses[0].state.terminated.exitCode,RESTARTS:.status.containerStatuses[0].restartCount"
```

### Kết quả cần chỉ cho lớp

- Manifest có labels, năm env và resources đúng.
- Log có sáu snapshot Flink thật.
- `REASON=Completed`, `EXIT_CODE=0`, `RESTARTS=0`.
- Thứ tự flag quan trọng: `--dry-run=client -o yaml` phải nằm trước
  `--command --`.

### Cleanup

```cmd
lab-1.1.bat cleanup
```

**Câu chốt:** dry-run sinh YAML để kiểm tra; `kubectl create -f` mới thay đổi
cluster.

[Tài liệu chi tiết Lab 1.1](./lab-1.1-60-second-pod.md)

---

<a id="lab-1-2"></a>

## Lab 1.2 — Init + Sidecar Pattern

**Thời lượng:** khoảng 60 phút<br>
**Mục tiêu:** xây multi-container Pod với init container, app, sidecar và chia
sẻ dữ liệu qua `emptyDir`.

### Điều cần trình bày

Luồng thật của Pod `init-sidecar-demo`:

```text
prepare-pipeline (init)
  -> chuẩn bị SQL/input và file log trong emptyDir
app
  -> chạy Flink SQL hữu hạn, ghi record LAB12 vào Kafka raw-data
  -> redirect output vào /var/log/app/app.log
sidecar
  -> tail cùng file log
Flink Deployment
  -> normalize record và ghi refined-data/Iceberg
```

Init container luôn hoàn thành trước app và sidecar. Hai `emptyDir` có vòng đời
bằng Pod, không phải persistent storage.

### Demo nhanh

```cmd
lab-1.2.bat run
```

### Demo thủ công

```cmd
kubectl delete -f .\lab-1.2-init-sidecar.yaml --ignore-not-found
kubectl apply --dry-run=server -f .\lab-1.2-init-sidecar.yaml
kubectl apply -f .\lab-1.2-init-sidecar.yaml
kubectl wait -n data-platform --for=condition=Initialized pod/init-sidecar-demo --timeout=120s
```

Xem thứ tự và trạng thái container:

```cmd
kubectl get pod init-sidecar-demo -n data-platform
kubectl get pod init-sidecar-demo -n data-platform -o jsonpath="{.status.initContainerStatuses[0].state}"
kubectl get pod init-sidecar-demo -n data-platform -o jsonpath="{range .status.containerStatuses[*]}{.name}{' ready='}{.ready}{' state='}{.state}{'\n'}{end}"
kubectl describe pod init-sidecar-demo -n data-platform
```

Chờ app hữu hạn kết thúc:

```cmd
kubectl wait -n data-platform --for=jsonpath="{.status.containerStatuses[?(@.name=='app')].state.terminated.exitCode}"=0 pod/init-sidecar-demo --timeout=240s
```

Đọc shared files từ sidecar và log qua đúng container:

```cmd
kubectl exec init-sidecar-demo -n data-platform -c sidecar -- cat /work/input.txt
kubectl logs init-sidecar-demo -n data-platform -c sidecar
kubectl exec init-sidecar-demo -n data-platform -c app -- cat /var/log/app/app.log
kubectl logs init-sidecar-demo -n data-platform -c app
```

`kubectl logs -c app` có thể rỗng vì app redirect stdout/stderr vào file dùng
chung. Đây là expected behavior; sidecar mới là container xuất file đó ra
stdout.

Chứng minh record đã đi qua pipeline:

```cmd
kubectl exec -n data-platform deployment/kafka -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic refined-data --from-beginning --timeout-ms 10000 2>nul | findstr /I "LAB12"
```

### Kết quả cần chỉ cho lớp

- Init container terminated với exit code `0`.
- App đã `Completed`, sidecar vẫn `Running`.
- Pod có thể hiện `1/2 Running` hoặc `NotReady` sau khi app hoàn thành; đây
  không phải lỗi sidecar.
- Log sidecar chứa dòng init, input và kết quả Flink SQL thật.
- YAML shell command có dấu `:` phải được quote nguyên chuỗi để tránh YAML
  parse thành mapping.

### Cleanup

```cmd
lab-1.2.bat cleanup
```

Record đã ghi vào Kafka/Iceberg vẫn tồn tại; cleanup chỉ xóa ConfigMap và Pod.

**Câu chốt:** init chuẩn bị dữ liệu một lần, app làm nghiệp vụ, sidecar cung cấp
khả năng bổ trợ cho app thông qua volume dùng chung.

[Tài liệu chi tiết Lab 1.2](./lab-1.2-init-sidecar.md)

---

<a id="lab-1-3"></a>

## Lab 1.3 — Jobs & CronJobs

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** chạy Job đến `Complete`, cấu hình `backoffLimit`, tạo CronJob theo
lịch và phân biệt chúng với Deployment.

### Điều cần trình bày

Job/CronJob chạy Flink SQL Client hữu hạn để insert record vào Kafka
`raw-data`. Flink Deployment đang chạy liên tục mới chịu trách nhiệm đọc Kafka,
normalize và ghi `refined-data`/Iceberg.

Không đặt `MedallionPipelineJob` streaming vào một Job: nguồn Kafka là
unbounded nên Job đó sẽ không bao giờ đạt `Complete`.

### Demo nhanh

```cmd
lab-1.3.bat run
```

Runner chờ một schedule thật ở đầu phút tiếp theo rồi tự suspend CronJob.

### Demo one-off Job

```cmd
kubectl apply -f .\lab-1.3-pipeline-sql.yaml
kubectl apply --dry-run=server -f .\lab-1.3-job.yaml
kubectl apply -f .\lab-1.3-job.yaml
kubectl wait -n data-platform --for=condition=complete job/ai-data-pipeline-once --timeout=240s
kubectl get job ai-data-pipeline-once -n data-platform
kubectl logs job/ai-data-pipeline-once -n data-platform
```

Kiểm tra policy:

```cmd
kubectl get job ai-data-pipeline-once -n data-platform -o jsonpath="{.spec.backoffLimit}"
kubectl get job ai-data-pipeline-once -n data-platform -o jsonpath="{.spec.template.spec.restartPolicy}"
kubectl describe job ai-data-pipeline-once -n data-platform
```

Giá trị cần thấy là `backoffLimit=3`, `restartPolicy=Never` và
`activeDeadlineSeconds=180`.

Kiểm tra output nghiệp vụ:

```cmd
kubectl exec -n data-platform deployment/kafka -- /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic refined-data --from-beginning --timeout-ms 10000 2>nul | findstr /I "LAB13 KUBERNETES"
```

`normalized_line` phải viết thường, trim và gộp whitespace.

### Demo CronJob

```cmd
kubectl apply -f .\lab-1.3-cronjob.yaml
kubectl get cronjob ai-data-pipeline-schedule -n data-platform
kubectl get cronjob ai-data-pipeline-schedule -n data-platform -o jsonpath="{.spec.schedule}{' timezone='}{.spec.timeZone}{' concurrency='}{.spec.concurrencyPolicy}{'\n'}"
```

Tạo một Job ngay từ template để không phải chờ lịch:

```cmd
kubectl delete job ai-data-pipeline-manual -n data-platform --ignore-not-found
kubectl create job ai-data-pipeline-manual -n data-platform --from=cronjob/ai-data-pipeline-schedule
kubectl wait -n data-platform --for=condition=complete job/ai-data-pipeline-manual --timeout=240s
kubectl logs job/ai-data-pipeline-manual -n data-platform
```

Chứng minh scheduler thật:

```cmd
kubectl get cronjob,job -n data-platform -l lab=1.3
kubectl get pods -n data-platform -l "app=ai-data-pipeline,workload=scheduled"
```

Suspend và resume:

```cmd
kubectl patch cronjob ai-data-pipeline-schedule -n data-platform -p "{\"spec\":{\"suspend\":true}}"
kubectl get cronjob ai-data-pipeline-schedule -n data-platform
kubectl patch cronjob ai-data-pipeline-schedule -n data-platform -p "{\"spec\":{\"suspend\":false}}"
```

### So sánh cần nói

| Resource | Nghiệp vụ | Trạng thái đích |
|---|---|---|
| Job | Chạy một batch hữu hạn | `Complete` |
| CronJob | Theo lịch sinh các Job | Job con `Complete`/`Failed` |
| Deployment | Duy trì stream processor/API dài hạn | Luôn `Available` |

`restartPolicy: Never` điều khiển container trong Pod; `backoffLimit` điều khiển
số lần Job controller thử lại bằng Pod.

### Cleanup

```cmd
lab-1.3.bat suspend
lab-1.3.bat cleanup
```

Record đã tạo là dữ liệu nghiệp vụ thật nên không bị xóa cùng Job.

**Câu chốt:** Job quản lý sự hoàn thành, CronJob quản lý thời điểm tạo Job,
Deployment quản lý tính sẵn sàng liên tục.

[Tài liệu chi tiết Lab 1.3](./lab-1.3-jobs-cronjobs.md)

---

<a id="lab-1-4"></a>

## Lab 1.4 — Label & Annotation Drill

**Thời lượng:** khoảng 30 phút<br>
**Mục tiêu:** bulk-create Pod, query bằng label selector, cập nhật hàng loạt và
dùng `--overwrite`.

### Điều cần trình bày

Sáu Pod audit hữu hạn thực hiện kiểm tra thật:

| Thành phần | Kiểm tra |
|---|---|
| Kafka | list topics và describe `raw-data` |
| Flink | CLI list jobs và REST `/jobs/overview` |
| Iceberg | list các bảng Medallion |
| MinIO | readiness HTTP 200 |

Pod đã `Completed` vẫn là Kubernetes object, do đó vẫn query, label và annotate
được.

### Demo nhanh

```cmd
lab-1.4.bat run
```

### Bulk-create và xem nghiệp vụ

```cmd
kubectl delete pods -n data-platform -l lab=1.4 --ignore-not-found
kubectl apply -f .\lab-1.4-label-annotation.yaml
kubectl wait -n data-platform --for=jsonpath="{.status.phase}"=Succeeded pod -l lab=1.4 --timeout=180s
kubectl get pods -n data-platform -l lab=1.4 -L env,tier,track,component
kubectl logs -n data-platform -l lab=1.4 --prefix=true --tail=80 --max-log-requests=6
```

### Query selector

Equality, inequality và set-based:

```cmd
kubectl get pods -n data-platform -l "lab=1.4,env=dev"
kubectl get pods -n data-platform -l "lab=1.4,env=prod,tier=serve"
kubectl get pods -n data-platform -l "lab=1.4,env!=prod"
kubectl get pods -n data-platform -l "lab=1.4,component in (kafka,flink)"
kubectl get pods -n data-platform -l "lab=1.4,env in (dev,prod),tier notin (serve)"
kubectl get pods -n data-platform -l "lab=1.4,track"
```

Quy tắc:

- Dấu phẩy là phép AND.
- `in (...)` là OR giữa các value của cùng một key.
- `track` nghĩa là key tồn tại; `!track` nghĩa là key không tồn tại.
- Trong `cmd`, selector có dấu ngoặc/khoảng trắng phải đặt trong dấu nháy kép.

### Bulk update và expected failure

```cmd
kubectl label pods -n data-platform -l lab=1.4 owner=franc
kubectl get pods -n data-platform -l lab=1.4 -L owner
```

Lệnh sau **phải thất bại** vì label `env` đã tồn tại:

```cmd
kubectl label pods -n data-platform -l "lab=1.4,env=dev" env=test
```

Sửa đúng bằng `--overwrite`:

```cmd
kubectl label pods -n data-platform -l "lab=1.4,env=dev" env=test --overwrite
kubectl label pods -n data-platform -l "lab=1.4,tier in (ingest,process)" team=data
kubectl label pods -n data-platform -l "lab=1.4,track=stable" track=blue --overwrite
kubectl label pod audit-iceberg-tables-dev -n data-platform track-
```

Annotation:

```cmd
kubectl annotate pods -n data-platform -l lab=1.4 lab.muoilt.vn/owner=franc
kubectl annotate pods -n data-platform -l lab=1.4 lab.muoilt.vn/owner="franc-nguyen" --overwrite
kubectl get pods -n data-platform -l lab=1.4 -o custom-columns="NAME:.metadata.name,OWNER:.metadata.annotations.lab\.muoilt\.vn/owner"
```

### Verify ma trận cuối

```cmd
kubectl get pods -n data-platform -l "lab=1.4,env=prod,tier=serve" --no-headers
kubectl get pods -n data-platform -l "lab=1.4,env=test" --no-headers
kubectl get pods -n data-platform -l "lab=1.4,team=data" --no-headers
kubectl get pods -n data-platform -l "lab=1.4,!track" --no-headers
kubectl get pods -n data-platform -l lab=1.4 -L env,tier,track,component,owner,team
```

Số dòng mong đợi lần lượt: `1`, `3`, `4`, `1`.

Label dùng để select/group object; annotation dùng cho metadata mô tả và không
query được bằng `-l`. Không bao giờ dùng `--all` trong bài vì namespace còn
workload project.

### Cleanup

```cmd
lab-1.4.bat cleanup
```

**Câu chốt:** label là metadata vận hành có thể chọn; đổi key đã tồn tại cần
`--overwrite`; hậu tố `key-` xóa label.

[Tài liệu chi tiết Lab 1.4](./lab-1.4-label-annotation.md)

# Day 2 — Application Deployment

<a id="lab-2-1"></a>

## Lab 2.1 — Rolling Update & Rollback

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** rolling update từ release v1 sang v2, theo dõi rollout, mô phỏng
release xấu và rollback.

### Điều cần trình bày

Deployment `pipeline-release-auditor` có ba replica. Mỗi Pod kiểm tra JAR thật
và audit Flink, Iceberg, MinIO. Hai release:

```text
v1 = mualanhlung017/ai-data-pipeline:1.0.1
v2 = mualanhlung017/ai-data-pipeline:1.0.2
```

Strategy:

```yaml
rollingUpdate:
  maxUnavailable: 0
  maxSurge: 1
```

Kubernetes giữ ba Pod khỏe và có thể tạo thêm một Pod trong rollout.

### Demo nhanh

```cmd
lab-2.1.bat run
```

### Deploy v1

```cmd
kubectl delete deployment pipeline-release-auditor -n data-platform --ignore-not-found
kubectl apply --dry-run=client -f .\lab-2.1-rolling-update.yaml
kubectl apply --dry-run=server -f .\lab-2.1-rolling-update.yaml
kubectl apply -f .\lab-2.1-rolling-update.yaml
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=120s
```

```cmd
kubectl get deployment pipeline-release-auditor -n data-platform
kubectl get pods -n data-platform -l lab=2.1 -o wide
kubectl get deployment pipeline-release-auditor -n data-platform -o jsonpath="{.spec.strategy}"
kubectl get deployment pipeline-release-auditor -n data-platform -o jsonpath="{.spec.template.spec.containers[0].image}"
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
kubectl logs -n data-platform -l lab=2.1 --prefix=true --tail=8 --max-log-requests=4
```

### Rolling update v1 sang v2

Nếu có hai cửa sổ `cmd`, cửa sổ thứ nhất theo dõi Pod:

```cmd
kubectl get pods -n data-platform -l lab=2.1 -w
```

Cửa sổ thứ hai cập nhật:

```cmd
kubectl set image deployment/pipeline-release-auditor auditor=mualanhlung017/ai-data-pipeline:1.0.2 -n data-platform
kubectl annotate deployment pipeline-release-auditor -n data-platform kubernetes.io/change-cause="Rolling update auditor from 1.0.1 to 1.0.2" --overwrite
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=120s
```

Nhấn `Ctrl+C` để dừng watch, rồi verify:

```cmd
kubectl get pods -n data-platform -l lab=2.1 -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image,IMAGE_ID:.status.containerStatuses[0].imageID"
kubectl get rs -n data-platform -l lab=2.1
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
kubectl logs -n data-platform -l lab=2.1 --prefix=true --tail=8 --max-log-requests=4
```

Pod cũ có thể ở `Terminating` vài giây do `preStop`; đó là graceful shutdown.

### Mô phỏng bad deployment

```cmd
kubectl set image deployment/pipeline-release-auditor auditor=mualanhlung017/ai-data-pipeline:ckad-bad-does-not-exist -n data-platform
kubectl annotate deployment pipeline-release-auditor -n data-platform kubernetes.io/change-cause="Simulate bad release with missing image" --overwrite
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=25s
```

`rollout status` **phải timeout**. Chẩn đoán:

```cmd
kubectl get deployment pipeline-release-auditor -n data-platform
kubectl get pods -n data-platform -l lab=2.1 -o wide
kubectl get rs -n data-platform -l lab=2.1
kubectl describe deployment pipeline-release-auditor -n data-platform
```

Kết quả cần nói:

- Pod mới ở `ErrImagePull`/`ImagePullBackOff`.
- Ba Pod v2 cũ vẫn `Ready`.
- Có thể thấy bốn Pod vì `maxSurge=1`.
- `maxUnavailable=0` ngăn controller chủ động xóa Pod khỏe khi Pod mới chưa
  qua readiness.

### Rollback

```cmd
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
kubectl rollout undo deployment/pipeline-release-auditor -n data-platform
kubectl annotate deployment pipeline-release-auditor -n data-platform kubernetes.io/change-cause="Rollback missing image to ai-data-pipeline:1.0.2" --overwrite
kubectl rollout status deployment/pipeline-release-auditor -n data-platform --timeout=120s
```

```cmd
kubectl get deployment pipeline-release-auditor -n data-platform -o jsonpath="{.spec.template.spec.containers[0].image}"
kubectl get pods -n data-platform -l lab=2.1
kubectl rollout history deployment/pipeline-release-auditor -n data-platform
```

Rollback về revision ngay trước bad release, tức v2 `1.0.2`, không phải v1.
Rollback dùng lại ReplicaSet cũ nhưng tạo revision lịch sử mới, nên số revision
có thể không liên tục.

### Cleanup

```cmd
lab-2.1.bat cleanup
```

**Câu chốt:** rollout status cho biết quá trình phát hành; readiness quyết định
khi nào Pod mới được thay Pod cũ; rollback khôi phục Pod template trước đó.

[Tài liệu chi tiết Lab 2.1](./lab-2.1-rolling-update.md)

---

<a id="lab-2-2"></a>

## Lab 2.2 — Blue/Green Switch

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** chạy đồng thời blue và green, rồi chuyển traffic bằng một Service
selector.

### Điều cần trình bày

```text
Service pipeline-release-gateway
selector track=blue|green
        |
        +--> blue: 2 Pods, image 1.0.1
        |
        +--> green: 2 Pods, image 1.0.2
```

Cả hai ReleaseGateway audit dependency thật. Service DNS, ClusterIP và port giữ
nguyên; chỉ EndpointSlice đổi.

### Demo nhanh

```cmd
lab-2.2.bat run
```

### Deploy hai màu

```cmd
kubectl apply --dry-run=server -f .\lab-2.2-blue-green.yaml
kubectl apply -f .\lab-2.2-blue-green.yaml
kubectl rollout status deployment/pipeline-release-blue -n data-platform --timeout=180s
kubectl rollout status deployment/pipeline-release-green -n data-platform --timeout=180s
kubectl get pods -n data-platform -l lab=2.2 -L track,release
```

### Chứng minh Service đang trỏ blue

```cmd
kubectl get service pipeline-release-gateway -n data-platform -o jsonpath="{.spec.clusterIP}{' selector='}{.spec.selector}{'\n'}"
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-release-gateway -o wide
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-release-gateway:8080/
```

Response cần có:

```text
color=blue
release=1.0.1
minio_http=200
```

### Flip sang green

```cmd
kubectl patch service pipeline-release-gateway -n data-platform --type=merge -p "{\"spec\":{\"selector\":{\"track\":\"green\"}}}"
kubectl get service pipeline-release-gateway -n data-platform -o jsonpath="{.spec.selector.track}"
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-release-gateway -o wide
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-release-gateway:8080/
```

Response phải đổi thành `color=green`, `release=1.0.2`.

Chứng minh Pod không bị restart:

```cmd
kubectl get pods -n data-platform -l lab=2.2 -L track,release
kubectl get deployment pipeline-release-blue pipeline-release-green -n data-platform
```

AGE và restart count của bốn Pod giữ nguyên.

### Switch back

```cmd
kubectl patch service pipeline-release-gateway -n data-platform --type=merge -p "{\"spec\":{\"selector\":{\"track\":\"blue\"}}}"
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-release-gateway:8080/
```

Không dùng `rollout undo` cho blue/green rollback vì blue vẫn chạy. Chỉ flip
selector ngược lại.

### Vấn đề cần giải thích

- Service chọn **Pod**, không chọn Deployment.
- Tất cả selector conditions là AND.
- Chỉ Pod khớp labels và đạt readiness mới trở thành endpoint.
- Switch rất nhanh nhưng hai môi trường chạy song song nên tốn tài nguyên hơn
  rolling update.

### Cleanup

```cmd
lab-2.2.bat cleanup
```

**Câu chốt:** blue/green tách việc deploy khỏi việc route traffic, nên rollback
chỉ là một selector flip.

[Tài liệu chi tiết Lab 2.2](./lab-2.2-blue-green.md)

---

<a id="lab-2-3"></a>

## Lab 2.3 — Scale & HPA

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** scale Deployment lên 10 replica và tạo HPA với CPU target 50%.

### Điều cần trình bày

`pipeline-normalizer-api` chạy logic thật của `LineNormalizer`:

```text
NFKC Unicode -> trim -> collapse whitespace -> lowercase Locale.ROOT
```

API `/work` chạy normalization nhiều vòng để tạo CPU load thật.

### Demo nhanh

```cmd
lab-2.3.bat run
```

### Kiểm tra Metrics API

```cmd
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

Nếu Metrics API chưa có:

```cmd
kubectl apply -f .\lab-2.3-metrics-server.yaml
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s
kubectl top nodes
```

Manifest local có `--kubelet-insecure-tls`; chỉ dùng cho Docker
Desktop/kind, không phải cấu hình production.

### Deploy API và kiểm tra nghiệp vụ

```cmd
kubectl apply -f .\lab-2.3-normalizer.yaml
kubectl rollout status deployment/pipeline-normalizer-api -n data-platform --timeout=180s
kubectl get pods -n data-platform -l lab=2.3 -L component
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://pipeline-normalizer:8080/normalize?line=%20%20DU%20%20%20LIEU%09AI%20%20"
```

Expected:

```text
normalized=du lieu ai
character_count=10
```

### Manual scale lên 10

Xóa HPA trước để HPA controller không ghi đè số replica:

```cmd
kubectl delete hpa pipeline-normalizer-api -n data-platform --ignore-not-found
kubectl scale deployment/pipeline-normalizer-api -n data-platform --replicas=10
kubectl rollout status deployment/pipeline-normalizer-api -n data-platform --timeout=180s
kubectl get deployment pipeline-normalizer-api -n data-platform
kubectl get deployment pipeline-normalizer-api -n data-platform -o jsonpath="{.spec.replicas}{' desired, '}{.status.readyReplicas}{' ready\n'}"
```

Cả desired và ready phải là `10`.

### Tạo HPA CPU 50%

Cách imperative:

```cmd
kubectl autoscale deployment pipeline-normalizer-api -n data-platform --min=2 --max=10 --cpu=50%
```

Hoặc dùng manifest `autoscaling/v2`:

```cmd
kubectl apply -f .\lab-2.3-hpa.yaml
```

```cmd
kubectl wait -n data-platform --for=condition=ScalingActive hpa/pipeline-normalizer-api --timeout=180s
kubectl get hpa pipeline-normalizer-api -n data-platform
kubectl describe hpa pipeline-normalizer-api -n data-platform
kubectl get hpa pipeline-normalizer-api -n data-platform -o jsonpath="{.spec.minReplicas}{'..'}{.spec.maxReplicas}{' cpu='}{.spec.metrics[0].resource.target.averageUtilization}{'%\n'}"
```

Container request là `100m`, nên 50% utilization tương ứng trung bình khoảng
`50m` CPU mỗi Pod. HPA dùng CPU **request** làm mẫu số, không dùng limit.

### Tạo load và quan sát

```cmd
kubectl delete job pipeline-normalizer-load -n data-platform --ignore-not-found
kubectl apply -f .\lab-2.3-load-job.yaml
```

Mở cửa sổ thứ hai:

```cmd
kubectl get hpa pipeline-normalizer-api -n data-platform -w
```

Ở cửa sổ chính:

```cmd
kubectl top pods -n data-platform -l "lab=2.3,component=normalizer-api"
kubectl get deployment pipeline-normalizer-api -n data-platform
kubectl wait -n data-platform --for=condition=complete job/pipeline-normalizer-load --timeout=180s
kubectl logs job/pipeline-normalizer-load -n data-platform
```

Vì manual scale đã ở `maxReplicas=10`, HPA không tăng quá 10. Khi load dừng,
HPA có thể giảm dần về `minReplicas=2` sau stabilization window.

Sau khi HPA tồn tại, `kubectl scale` chỉ có thể có hiệu lực tạm thời vì HPA sẽ
reconcile lại trường replicas.

### Cleanup

```cmd
lab-2.3.bat cleanup
```

Chỉ khi Metrics Server do lab cài và không dùng cho bài khác:

```cmd
lab-2.3.bat cleanup-metrics
```

**Câu chốt:** manual scale đặt desired replicas trực tiếp; HPA liên tục tính
desired replicas từ metrics, request và giới hạn min/max.

[Tài liệu chi tiết Lab 2.3](./lab-2.3-scale-hpa.md)

---

<a id="lab-2-4"></a>

## Lab 2.4 — Kustomize Overlay

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** dùng một base, tạo dev/prod overlays, patch image và replica mà
không copy Deployment.

### Cấu trúc cần trình bày

```text
lab-2.4/
|-- base/
|   |-- deployment.yaml
|   `-- kustomization.yaml
`-- overlays/
    |-- dev/kustomization.yaml
    `-- prod/kustomization.yaml
```

| Overlay | Tên sau render | Image | Replicas |
|---|---|---|---:|
| dev | `pipeline-kustomize-auditor-dev` | `1.0.1` | 1 |
| prod | `pipeline-kustomize-auditor-prod` | `1.0.2` | 3 |

Workload vẫn audit JAR, Flink, Iceberg và MinIO thật. Overlay chỉ thay cấu hình
triển khai.

### Demo nhanh

```cmd
lab-2.4.bat run
```

### Render, chưa thay đổi cluster

```cmd
kubectl kustomize .\lab-2.4\overlays\dev
kubectl kustomize .\lab-2.4\overlays\prod
```

Lọc các trường chính:

```cmd
kubectl kustomize .\lab-2.4\overlays\dev | findstr /C:"name: pipeline-kustomize-auditor-dev" /C:"replicas:" /C:"image:"
kubectl kustomize .\lab-2.4\overlays\prod | findstr /C:"name: pipeline-kustomize-auditor-prod" /C:"replicas:" /C:"image:"
```

Server-side validate bản đã render:

```cmd
kubectl kustomize .\lab-2.4\overlays\dev | kubectl apply --dry-run=server -f -
kubectl kustomize .\lab-2.4\overlays\prod | kubectl apply --dry-run=server -f -
```

### Apply dev

```cmd
kubectl apply -k .\lab-2.4\overlays\dev
kubectl rollout status deployment/pipeline-kustomize-auditor-dev -n data-platform --timeout=120s
kubectl get deployment pipeline-kustomize-auditor-dev -n data-platform -o jsonpath="{.spec.replicas}{' image='}{.spec.template.spec.containers[0].image}{'\n'}"
kubectl get pods -n data-platform -l "lab=2.4,environment=dev"
kubectl logs -n data-platform -l "lab=2.4,environment=dev" --prefix=true --tail=8
```

### Apply prod từ cùng base

```cmd
kubectl apply -k .\lab-2.4\overlays\prod
kubectl rollout status deployment/pipeline-kustomize-auditor-prod -n data-platform --timeout=120s
kubectl get deployment pipeline-kustomize-auditor-prod -n data-platform -o jsonpath="{.spec.replicas}{' image='}{.spec.template.spec.containers[0].image}{'\n'}"
kubectl get pods -n data-platform -l "lab=2.4,environment=prod"
kubectl logs -n data-platform -l "lab=2.4,environment=prod" --prefix=true --tail=8 --max-log-requests=4
```

### Diff và điểm dễ nhầm

```cmd
kubectl diff -k .\lab-2.4\overlays\prod
```

`kubectl diff` trả exit code `1` khi có khác biệt; nghĩa là “có diff”, không
nhất thiết là lỗi cluster.

- `kubectl kustomize DIR`: chỉ render.
- `kubectl apply -k DIR`: render rồi apply.
- Không dùng `kubectl apply -f kustomization.yaml`.
- Base là nguồn dùng chung; overlay chứa phần khác biệt tối thiểu.

### Cleanup

```cmd
lab-2.4.bat cleanup
```

Hoặc:

```cmd
kubectl delete -k .\lab-2.4\overlays\dev --ignore-not-found
kubectl delete -k .\lab-2.4\overlays\prod --ignore-not-found
```

**Câu chốt:** Kustomize biến một base thành nhiều cấu hình môi trường mà không
nhân bản manifest.

[Tài liệu chi tiết Lab 2.4](./lab-2.4-kustomize.md)

# Day 3 — Environment, Configuration & Security

<a id="lab-3-1"></a>

## Lab 3.1 — ConfigMap & Secret Injection

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** tạo Secret từ file, ConfigMap từ literal, inject Secret thành env
và mount ConfigMap thành volume trong cùng một Pod.

### Điều cần trình bày

Pod `pipeline-config-auditor` nhận:

```text
Secret pipeline-catalog-secret
  key catalog-client.token -> env CATALOG_CLIENT_TOKEN

ConfigMap pipeline-endpoints
  flink.jobs.url
  iceberg.tables.url       -> files trong /etc/pipeline/endpoints
  minio.ready.url
```

Pod dùng cấu hình này để gọi dependency thật. Nó chỉ log SHA-256 fingerprint
của token, không log plaintext.

### Demo nhanh

```cmd
lab-3.1.bat run
```

### Tạo Secret từ file

```cmd
kubectl delete pod pipeline-config-auditor -n data-platform --ignore-not-found
kubectl delete secret pipeline-catalog-secret -n data-platform --ignore-not-found
kubectl create secret generic pipeline-catalog-secret -n data-platform --from-file=catalog-client.token=.\lab-3.1-files\catalog-client.token.example
kubectl label secret pipeline-catalog-secret -n data-platform app=ai-data-pipeline lab=3.1 component=config-auditor
kubectl get secret pipeline-catalog-secret -n data-platform
kubectl describe secret pipeline-catalog-secret -n data-platform
```

`describe` cho thấy tên key và kích thước, không cần decode credential trước
lớp.

### Tạo ConfigMap từ literal

```cmd
kubectl delete configmap pipeline-endpoints -n data-platform --ignore-not-found
kubectl create configmap pipeline-endpoints -n data-platform --from-literal=flink.jobs.url=http://flink-jobmanager:8081/jobs/overview --from-literal=iceberg.tables.url=http://iceberg-rest:8181/v1/namespaces/medallion/tables --from-literal=minio.ready.url=http://minio:9000/minio/health/ready
kubectl label configmap pipeline-endpoints -n data-platform app=ai-data-pipeline lab=3.1 component=config-auditor
kubectl get configmap pipeline-endpoints -n data-platform -o yaml
```

ConfigMap dùng cho dữ liệu cấu hình không nhạy cảm; không dùng nó để lưu
password/token.

### Inject vào Pod và verify

```cmd
kubectl apply --dry-run=server -f .\lab-3.1-config-secret-pod.yaml
kubectl apply -f .\lab-3.1-config-secret-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-config-auditor --timeout=120s
```

```cmd
kubectl get pod pipeline-config-auditor -n data-platform -o jsonpath="{.spec.containers[0].env[0].valueFrom.secretKeyRef.name}{'\n'}"
kubectl get pod pipeline-config-auditor -n data-platform -o jsonpath="{.spec.volumes[0].configMap.name}{'\n'}"
kubectl exec pipeline-config-auditor -n data-platform -- ls -l /etc/pipeline/endpoints
kubectl exec pipeline-config-auditor -n data-platform -- cat /etc/pipeline/endpoints/flink.jobs.url
kubectl exec pipeline-config-auditor -n data-platform -- cat /etc/pipeline/endpoints/iceberg.tables.url
kubectl exec pipeline-config-auditor -n data-platform -- cat /etc/pipeline/endpoints/minio.ready.url
kubectl logs pipeline-config-auditor -n data-platform --tail=10
```

Expected:

- Secret reference là `pipeline-catalog-secret`.
- Volume source là `pipeline-endpoints`.
- Flink có job `RUNNING`, Iceberg có ba bảng Medallion, MinIO HTTP 200.
- Log có fingerprint nhưng không có token plaintext.

Env và phần lớn Pod spec là immutable sau khi Pod tồn tại; thay cấu hình env
thường cần controller tạo Pod mới. ConfigMap volume có thể được kubelet cập nhật
sau một khoảng trễ, nhưng ứng dụng cũng phải tự reload.

### Cleanup

```cmd
lab-3.1.bat cleanup
```

**Câu chốt:** Secret và ConfigMap tách cấu hình khỏi image; `secretKeyRef` lấy
một key vào env, còn ConfigMap volume biến mỗi key thành file.

[Tài liệu chi tiết Lab 3.1](./lab-3.1-configmap-secret.md)

---

<a id="lab-3-2"></a>

## Lab 3.2 — Security Context Lockdown

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** chạy non-root, root filesystem read-only, drop capabilities và
cấm privilege escalation.

### Điều cần trình bày

Pod `pipeline-secure-auditor` vẫn audit JAR/Flink/Iceberg/MinIO thật nhưng không
cần root hay Kubernetes API token.

Pod-level:

```yaml
runAsNonRoot: true
runAsUser: 10001
runAsGroup: 10001
fsGroup: 10001
seccompProfile:
  type: RuntimeDefault
```

Container-level:

```yaml
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: [ALL]
```

Pod còn đặt `automountServiceAccountToken: false`. Một `emptyDir` giới hạn
`16Mi` được mount tại `/tmp` làm vùng ghi rõ ràng.

### Demo nhanh

```cmd
lab-3.2.bat run
```

### Validate và deploy

```cmd
kubectl apply --dry-run=client -f .\lab-3.2-security-context.yaml
kubectl apply --dry-run=server -f .\lab-3.2-security-context.yaml
kubectl apply -f .\lab-3.2-security-context.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-secure-auditor --timeout=120s
```

### Kiểm tra spec

```cmd
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.securityContext.runAsNonRoot}{'\n'}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.securityContext.runAsUser}{'\n'}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.containers[0].securityContext.readOnlyRootFilesystem}{'\n'}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.containers[0].securityContext.allowPrivilegeEscalation}{'\n'}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.containers[0].securityContext.capabilities.drop[0]}{'\n'}"
kubectl get pod pipeline-secure-auditor -n data-platform -o jsonpath="{.spec.automountServiceAccountToken}{'\n'}"
```

Expected: `true`, `10001`, `true`, `false`, `ALL`, `false`.

### Kiểm tra runtime và expected failure

```cmd
kubectl exec pipeline-secure-auditor -n data-platform -- id
```

Phải thấy `uid=10001`, `gid=10001`.

Ghi vào root filesystem **phải thất bại**:

```cmd
kubectl exec pipeline-secure-auditor -n data-platform -- touch /rootfs-write-test
```

Ghi vào volume `/tmp` phải thành công:

```cmd
kubectl exec pipeline-secure-auditor -n data-platform -- touch /tmp/secure-write-test
kubectl exec pipeline-secure-auditor -n data-platform -- ls -l /tmp/secure-write-test
kubectl exec pipeline-secure-auditor -n data-platform -- rm /tmp/secure-write-test
kubectl logs pipeline-secure-auditor -n data-platform --tail=10
```

Root filesystem read-only không có nghĩa ứng dụng không được ghi bất kỳ đâu;
ứng dụng cần mount volume writable tối thiểu vào đúng path cần thiết.

Pod-level tạo default cho containers; capabilities,
`readOnlyRootFilesystem` và `allowPrivilegeEscalation` thuộc container-level.

### Cleanup

```cmd
lab-3.2.bat cleanup
```

**Câu chốt:** least privilege không chỉ là non-root; cần giảm filesystem,
capabilities, escalation, syscall profile và token không cần thiết.

[Tài liệu chi tiết Lab 3.2](./lab-3.2-security-context.md)

---

<a id="lab-3-3"></a>

## Lab 3.3 — ServiceAccount & RBAC

**Thời lượng:** khoảng 60 phút<br>
**Mục tiêu:** tạo ServiceAccount, Role, RoleBinding và cho Pod dùng token để
list Pods trong namespace.

### Luồng quyền cần trình bày

```text
Pod pipeline-rbac-observer
  -> ServiceAccount pipeline-observer
  -> RoleBinding pipeline-observer-reads-pods
  -> Role pipeline-pod-reader
  -> get/list/watch pods trong data-platform
```

Role là namespace-scoped và không có quyền với Secrets, không có write verbs,
không dùng wildcard.

### Demo nhanh

```cmd
lab-3.3.bat run
```

### Validate đúng thứ tự

```cmd
kubectl apply --dry-run=client -f .\lab-3.3-serviceaccount-rbac.yaml
kubectl apply --dry-run=client -f .\lab-3.3-observer-pod.yaml
kubectl apply --dry-run=server -f .\lab-3.3-serviceaccount-rbac.yaml
kubectl apply -f .\lab-3.3-serviceaccount-rbac.yaml
kubectl apply --dry-run=server -f .\lab-3.3-observer-pod.yaml
```

Server-side dry-run của Pod cần ServiceAccount đã tồn tại, vì API server kiểm
tra reference này.

### Apply và xem object

```cmd
kubectl apply -f .\lab-3.3-observer-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-rbac-observer --timeout=120s
kubectl get serviceaccount pipeline-observer -n data-platform
kubectl get role pipeline-pod-reader -n data-platform -o yaml
kubectl get rolebinding pipeline-observer-reads-pods -n data-platform -o yaml
kubectl get pod pipeline-rbac-observer -n data-platform
```

### Kiểm tra positive/negative permission

```cmd
kubectl auth can-i list pods --as=system:serviceaccount:data-platform:pipeline-observer -n data-platform
kubectl auth can-i list secrets --as=system:serviceaccount:data-platform:pipeline-observer -n data-platform
kubectl auth can-i create pods --as=system:serviceaccount:data-platform:pipeline-observer -n data-platform
kubectl auth can-i --list --as=system:serviceaccount:data-platform:pipeline-observer -n data-platform
```

Kết quả lần lượt phải là `yes`, `no`, `no`.

### Chứng minh request phát ra từ Pod

```cmd
kubectl get pod pipeline-rbac-observer -n data-platform -o jsonpath="{.spec.serviceAccountName}{'\n'}"
kubectl exec pipeline-rbac-observer -n data-platform -- ls -l /var/run/secrets/kubernetes.io/serviceaccount
kubectl logs pipeline-rbac-observer -n data-platform --tail=10
```

Log phải có `http=200` và danh sách Pod pipeline. Token được đọc từ projected
volume nhưng không được in.

Nếu endpoint đổi sang Secrets, API server sẽ trả `403 Forbidden`. Đây là bằng
chứng RoleBinding hoạt động và least privilege được giữ.

Imperative CKAD equivalent:

```cmd
kubectl create serviceaccount pipeline-observer -n data-platform
kubectl create role pipeline-pod-reader -n data-platform --verb=get,list,watch --resource=pods
kubectl create rolebinding pipeline-observer-reads-pods -n data-platform --role=pipeline-pod-reader --serviceaccount=data-platform:pipeline-observer
```

### Cleanup

```cmd
lab-3.3.bat cleanup
```

**Câu chốt:** ServiceAccount là identity, Role là permission, RoleBinding nối
identity với permission trong namespace.

[Tài liệu chi tiết Lab 3.3](./lab-3.3-serviceaccount-rbac.md)

---

<a id="lab-3-4"></a>

## Lab 3.4 — Namespace Quotas

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** áp ResourceQuota và LimitRange, rồi quan sát admission từ chối
Pod làm vượt quota.

### Điều cần trình bày

Lab dùng namespace riêng `pipeline-quota-lab`; không thử quota trong
`data-platform` vì có thể chặn rollout của Kafka/Flink/Iceberg/MinIO.

LimitRange inject mặc định cho mỗi container không khai báo resources:

| Trường | CPU | Memory |
|---|---:|---:|
| request | `100m` | `64Mi` |
| limit | `200m` | `128Mi` |

Quota chính:

```text
pods=2
requests.cpu=150m
requests.memory=192Mi
limits.cpu=300m
limits.memory=384Mi
```

Pod thứ nhất dùng default và được nhận. Pod thứ hai làm tổng request CPU thành
`200m > 150m` và tổng limit thành `400m > 300m`, nên bị từ chối dù `pods=2`
chưa đầy.

### Demo nhanh

```cmd
lab-3.4.bat run
```

### Tạo namespace và policy

```cmd
kubectl apply -f .\lab-3.4-namespace.yaml
kubectl wait --for=jsonpath="{.status.phase}"=Active namespace/pipeline-quota-lab --timeout=60s
kubectl apply --dry-run=server -f .\lab-3.4-quota-policy.yaml
kubectl apply -f .\lab-3.4-quota-policy.yaml
kubectl get limitrange,resourcequota -n pipeline-quota-lab
kubectl describe limitrange pipeline-container-defaults -n pipeline-quota-lab
kubectl describe resourcequota pipeline-compute-quota -n pipeline-quota-lab
```

Namespace phải tồn tại trước server-side dry-run của object namespaced.

### Pod được admission chấp nhận

Manifest cố ý không khai báo `resources`:

```cmd
kubectl apply -f .\lab-3.4-allowed-pod.yaml
kubectl wait -n pipeline-quota-lab --for=condition=Ready pod/quota-auditor-allowed --timeout=120s
kubectl get pod quota-auditor-allowed -n pipeline-quota-lab -o jsonpath="{.spec.containers[0].resources}{'\n'}"
kubectl describe resourcequota pipeline-compute-quota -n pipeline-quota-lab
kubectl logs quota-auditor-allowed -n pipeline-quota-lab --tail=10
```

Stored Pod spec đã có requests/limits do LimitRange admission inject.

### Pod bị quota từ chối

```cmd
kubectl apply -f .\lab-3.4-overflow-pod.yaml
```

Lệnh **phải thất bại** với `forbidden: exceeded quota`.

```cmd
kubectl get pod quota-auditor-overflow -n pipeline-quota-lab
kubectl describe resourcequota pipeline-compute-quota -n pipeline-quota-lab
```

Pod phải `NotFound`: request bị từ chối trước khi object được lưu, nên không có
Pod status/log/event để xem.

### Phân biệt cần nói

- LimitRange default/validate tài nguyên từng container/Pod.
- ResourceQuota giới hạn tổng requests/limits/object count của namespace.
- LimitRange inject trước, ResourceQuota tính cả giá trị đã inject.
- Quota không tự chia đều tài nguyên cho từng Pod.

### Cleanup

```cmd
lab-3.4.bat cleanup
```

Lệnh này xóa cả namespace lab; `data-platform` không bị ảnh hưởng.

**Câu chốt:** LimitRange bảo vệ từng workload, ResourceQuota bảo vệ tổng ngân
sách namespace, và cả hai được thực thi tại admission.

[Tài liệu chi tiết Lab 3.4](./lab-3.4-namespace-quotas.md)

# Day 4 — Networking & Storage

<a id="lab-4-1"></a>

## Lab 4.1 — ClusterIP & NodePort

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** tạo backend ClusterIP, frontend NodePort, chẩn đoán selector
mismatch và kiểm tra Endpoints.

### Kiến trúc cần trình bày

```text
NodeIP:30081
  -> Service pipeline-frontend (NodePort)
  -> frontend Pod
  -> Service pipeline-backend (ClusterIP)
  -> 2 backend Pods
  -> LineNormalizer thật
```

Lỗi được cài chủ động:

```text
Pod label:        component=normalizer-backend
Service selector: component=normalizer-backend-broken
```

Service tồn tại nhưng không có endpoint; frontend `/api` trả 502.

### Demo nhanh

```cmd
lab-4.1.bat run
```

### Deploy trạng thái lỗi

```cmd
kubectl apply --dry-run=server -f .\lab-4.1-services.yaml
kubectl apply -f .\lab-4.1-services.yaml
kubectl rollout status deployment/pipeline-backend -n data-platform --timeout=120s
kubectl rollout status deployment/pipeline-frontend -n data-platform --timeout=120s
kubectl get service pipeline-backend pipeline-frontend -n data-platform
```

Expected: backend `ClusterIP`; frontend `NodePort` với `8080:30081/TCP`.

### Diagnose selector mismatch

```cmd
kubectl get service pipeline-backend -n data-platform -o jsonpath="{.spec.selector}{'\n'}"
kubectl get pods -n data-platform -l lab=4.1 --show-labels
kubectl get pods -n data-platform -l "app=ai-data-pipeline,lab=4.1,component=normalizer-backend-broken"
kubectl get endpoints pipeline-backend -n data-platform
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-backend
kubectl describe service pipeline-backend -n data-platform
```

Không có Pod match selector; Endpoints phải `<none>`. Nếu Kubernetes cảnh báo
Endpoints API cũ, dùng EndpointSlice là API hiện đại.

### Fix selector

```cmd
kubectl patch service pipeline-backend -n data-platform --type=merge -p "{\"spec\":{\"selector\":{\"app\":\"ai-data-pipeline\",\"lab\":\"4.1\",\"component\":\"normalizer-backend\"}}}"
kubectl get endpoints pipeline-backend -n data-platform
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-backend -o wide
```

Phải có hai backend Pod IP ở port 8080.

### Verify ClusterIP và nghiệp vụ normalize

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://pipeline-backend:8080/api?line=%20%20DU%20%20%20LIEU%09AI%20%20"
```

Expected:

```text
component=backend
normalized=du lieu ai
character_count=10
```

### Verify NodePort không hard-code Node IP

```cmd
for /f "tokens=1,2 delims==" %A in ('kubectl get nodes -o jsonpath^="{range .items[0].status.addresses[*]}{.type}={.address}{'\n'}{end}"') do if "%A"=="InternalIP" set "NODE_IP=%B"
for /f "delims=" %P in ('kubectl get service pipeline-frontend -n data-platform -o jsonpath^="{.spec.ports[0].nodePort}"') do set "NODE_PORT=%P"
echo NODE_IP=%NODE_IP% NODE_PORT=%NODE_PORT%
```

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%NODE_PORT%/"
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%NODE_PORT%/api?line=KUBERNETES%20DATA"
```

Response thứ hai phải cho thấy frontend route tới backend và normalize thành
`kubernetes data`.

Docker local có thể không publish NodePort thẳng ra Windows host. Request từ
Pod tới Node IP vẫn kiểm tra đúng kube-proxy/NodePort path. Nếu muốn mở từ host:

```cmd
kubectl port-forward -n data-platform service/pipeline-frontend 18081:8080
```

Mở `http://localhost:18081` trong trình duyệt; `Ctrl+C` để dừng.

### Cleanup

```cmd
lab-4.1.bat cleanup
```

**Câu chốt:** Service selector sai không làm Pod lỗi; nó làm EndpointSlice rỗng.
Luôn so sánh selector với Pod labels trước.

[Tài liệu chi tiết Lab 4.1](./lab-4.1-clusterip-nodeport.md)

---

<a id="lab-4-2"></a>

## Lab 4.2 — Ingress Routing

**Thời lượng:** khoảng 60 phút<br>
**Mục tiêu:** route `/` tới frontend và `/api` trực tiếp tới backend bằng
Ingress.

### Kiến trúc cần trình bày

```text
Ingress controller
  |-- Prefix /api -> pipeline-backend:8080
  `-- Prefix /    -> pipeline-frontend:8080
```

Khi cả hai path match, prefix dài hơn `/api` được ưu tiên.

Ingress object chỉ là rule; muốn có data plane phải có Ingress controller.
Local runner dùng ingress-nginx `controller-v1.15.1` đã pin để luyện API. Dự án
ingress-nginx đã kết thúc bảo trì, vì vậy không coi đây là lựa chọn production
mới.

### Demo nhanh

```cmd
lab-4.2.bat run
```

### Chuẩn bị app Lab 4.1

```cmd
lab-4.1.bat run
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-backend
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-frontend
```

### Kiểm tra/cài controller local

```cmd
kubectl get ingressclass
kubectl get deployment,service -n ingress-nginx
```

Chỉ khi chưa có controller:

```cmd
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s
kubectl wait -n ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
```

### Apply Ingress

```cmd
kubectl apply --dry-run=server -f .\lab-4.2-ingress.yaml
kubectl apply -f .\lab-4.2-ingress.yaml
kubectl get ingress pipeline-routing -n data-platform
kubectl describe ingress pipeline-routing -n data-platform
```

`describe` phải hiện:

```text
/api -> pipeline-backend:8080
/    -> pipeline-frontend:8080
```

Cột `ADDRESS` có thể trống với bare-metal controller nhưng NodePort vẫn route.

### Lấy endpoint động và verify

```cmd
for /f "tokens=1,2 delims==" %A in ('kubectl get nodes -o jsonpath^="{range .items[0].status.addresses[*]}{.type}={.address}{'\n'}{end}"') do if "%A"=="InternalIP" set "NODE_IP=%B"
for /f "delims=" %P in ('kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath^="{.spec.ports[0].nodePort}"') do set "INGRESS_PORT=%P"
echo NODE_IP=%NODE_IP% INGRESS_PORT=%INGRESS_PORT%
```

Route `/`:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%INGRESS_PORT%/"
```

Expected `component=frontend`.

Route `/api`:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://%NODE_IP%:%INGRESS_PORT%/api?line=%20INGRESS%20DATA%20"
```

Expected `component=backend`, `normalized=ingress data` và không có
`routed_by=frontend-service`, vì controller đi thẳng backend.

### Troubleshooting khi request lỗi

```cmd
kubectl get ingressclass
kubectl describe ingress pipeline-routing -n data-platform
kubectl get service,endpointslice -n data-platform
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

Kiểm tra theo thứ tự: controller, `ingressClassName`, rule/path, Service port,
EndpointSlice.

### Cleanup

```cmd
lab-4.2.bat cleanup
lab-4.1.bat cleanup
```

Chỉ gỡ controller nếu chính lab đã cài:

```cmd
lab-4.2.bat cleanup-controller
```

**Câu chốt:** Ingress khai báo HTTP routing; controller mới thực thi rule, còn
Service/EndpointSlice vẫn là đích cuối bên trong cluster.

[Tài liệu chi tiết Lab 4.2](./lab-4.2-ingress-routing.md)

---

<a id="lab-4-3"></a>

## Lab 4.3 — NetworkPolicy Isolation

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** chỉ cho frontend gọi backend và chặn backend egress ra internet.

### Điều cần trình bày

Policy chỉ select hai backend Pods. Khi một Pod được select cho ingress/egress,
NetworkPolicy trở thành allow-list:

```text
Ingress allow:
  frontend Pods cùng namespace -> backend TCP 8080

Egress allow:
  backend -> CoreDNS UDP/TCP 53

Mọi traffic khác:
  bị chặn
```

NetworkPolicy không có action `deny`. “Deny internet” đạt được bằng cách chỉ
allow DNS và không có rule allow `0.0.0.0/0`.

### Demo nhanh

```cmd
lab-4.3.bat run
```

### Chuẩn bị và kiểm tra CNI

```cmd
lab-4.1.bat run
kubectl get daemonset kindnet -n kube-system -o wide
kubectl get pods -n kube-system -l k8s-app=kindnet
kubectl delete networkpolicy pipeline-backend-isolation -n data-platform --ignore-not-found
```

API server có thể lưu NetworkPolicy nhưng CNI mới là thành phần enforce packet.

### Baseline trước policy

Frontend gọi backend:

```cmd
kubectl exec -n data-platform deployment/pipeline-frontend -c frontend -- /usr/bin/curl -fsS http://pipeline-backend:8080/api?line=frontend-baseline
```

Flink Pod gọi thẳng backend:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-backend:8080/api?line=unauthorized-baseline
```

Backend ra internet:

```cmd
kubectl exec -n data-platform deployment/pipeline-backend -c backend -- /usr/bin/curl -fsS --max-time 10 https://example.com
```

Cả ba phải thành công để so sánh sau policy có ý nghĩa.

### Apply policy

```cmd
kubectl apply --dry-run=server -f .\lab-4.3-networkpolicy.yaml
kubectl apply -f .\lab-4.3-networkpolicy.yaml
kubectl describe networkpolicy pipeline-backend-isolation -n data-platform
```

### Positive tests

Frontend vẫn gọi trực tiếp backend:

```cmd
kubectl exec -n data-platform deployment/pipeline-frontend -c frontend -- /usr/bin/curl -fsS --max-time 5 http://pipeline-backend:8080/api?line=frontend-allowed
```

Flink gọi frontend, rồi frontend gọi backend:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 5 http://pipeline-frontend:8080/api?line=proxy-allowed
```

Hai request phải thành công.

### Negative tests

Flink gọi thẳng backend **phải timeout/fail**:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 3 http://pipeline-backend:8080/api?line=must-be-denied
```

DNS từ backend vẫn được allow:

```cmd
kubectl exec -n data-platform deployment/pipeline-backend -c backend -- getent hosts example.com
```

HTTPS internet từ backend **phải timeout/fail**:

```cmd
kubectl exec -n data-platform deployment/pipeline-backend -c backend -- /usr/bin/curl -fsS --max-time 3 https://example.com
```

Service và EndpointSlice vẫn tồn tại trong negative ingress test; packet bị CNI
chặn sau khi Service đã chọn endpoint.

Nếu negative test vẫn thành công, CNI không enforce policy hoặc selector không
chọn đúng Pod.

Policy này cũng chặn ingress-nginx gọi trực tiếp `/api` vì controller không mang
label frontend. Route `/` tới frontend rồi frontend proxy sang backend vẫn hợp
lệ.

### Cleanup

```cmd
lab-4.3.bat cleanup
lab-4.1.bat cleanup
```

**Câu chốt:** NetworkPolicy là allow-list áp vào Pod được selector chọn; DNS
thường phải được allow riêng nếu khóa egress.

[Tài liệu chi tiết Lab 4.3](./lab-4.3-networkpolicy.md)

---

<a id="lab-4-4"></a>

## Lab 4.4 — Persistent Volume Claims

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** provision PVC 1Gi động, ghi snapshot, xóa/tạo lại Pod và chứng
minh dữ liệu còn nguyên.

### Điều cần trình bày

PVC:

```text
name: pipeline-audit-state
storageClassName: standard
capacity: 1Gi
accessModes: ReadWriteOnce
```

Pod ghi một lần file:

```text
/var/lib/pipeline-state/dependency-audit.log
```

File chứa SHA-256 JAR, Flink jobs, Iceberg tables và MinIO status thật. Nếu file
đã tồn tại, Pod mới không overwrite mà log `persistent_state_reused`.

StorageClass local dùng `WaitForFirstConsumer`, nên PVC có thể `Pending` cho tới
khi Pod consumer được schedule.

### Demo nhanh

```cmd
lab-4.4.bat run
```

### Validate và provision

```cmd
kubectl get storageclass
kubectl apply --dry-run=client -f .\lab-4.4-pvc.yaml
kubectl apply --dry-run=server -f .\lab-4.4-pvc.yaml
kubectl apply -f .\lab-4.4-pvc.yaml
kubectl get pvc pipeline-audit-state -n data-platform
```

PVC `Pending` ở bước này có thể là đúng.

```cmd
kubectl apply --dry-run=server -f .\lab-4.4-pvc-pod.yaml
kubectl apply -f .\lab-4.4-pvc-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-pvc-auditor --timeout=120s
kubectl wait -n data-platform --for=jsonpath="{.status.phase}"=Bound pvc/pipeline-audit-state --timeout=120s
kubectl get pvc pipeline-audit-state -n data-platform -o wide
kubectl get pv
kubectl describe pvc pipeline-audit-state -n data-platform
```

### Ghi nhận state lần đầu

```cmd
kubectl logs pipeline-pvc-auditor -n data-platform
kubectl exec pipeline-pvc-auditor -n data-platform -- cat /var/lib/pipeline-state/dependency-audit.log
kubectl exec pipeline-pvc-auditor -n data-platform -- sha256sum /var/lib/pipeline-state/dependency-audit.log
```

Lưu UID và checksum vào biến `cmd`:

```cmd
for /f "delims=" %U in ('kubectl get pod pipeline-pvc-auditor -n data-platform -o jsonpath^="{.metadata.uid}"') do set "OLD_UID=%U"
for /f %S in ('kubectl exec pipeline-pvc-auditor -n data-platform -- sha256sum /var/lib/pipeline-state/dependency-audit.log') do set "OLD_SHA=%S"
echo OLD_UID=%OLD_UID% OLD_SHA=%OLD_SHA%
```

Log lần đầu phải có `persistent_state_created`.

### Xóa Pod nhưng giữ PVC

```cmd
kubectl delete pod pipeline-pvc-auditor -n data-platform --wait=true
kubectl get pvc pipeline-audit-state -n data-platform
```

PVC vẫn `Bound`.

### Tạo Pod mới và so sánh

```cmd
kubectl apply -f .\lab-4.4-pvc-pod.yaml
kubectl wait -n data-platform --for=condition=Ready pod/pipeline-pvc-auditor --timeout=120s
kubectl logs pipeline-pvc-auditor -n data-platform
for /f "delims=" %U in ('kubectl get pod pipeline-pvc-auditor -n data-platform -o jsonpath^="{.metadata.uid}"') do set "NEW_UID=%U"
for /f %S in ('kubectl exec pipeline-pvc-auditor -n data-platform -- sha256sum /var/lib/pipeline-state/dependency-audit.log') do set "NEW_SHA=%S"
echo OLD_UID=%OLD_UID%
echo NEW_UID=%NEW_UID%
echo OLD_SHA=%OLD_SHA%
echo NEW_SHA=%NEW_SHA%
```

Expected:

- `OLD_UID` khác `NEW_UID`: đây là Pod object mới.
- `OLD_SHA` bằng `NEW_SHA`: file trên volume không đổi.
- Log mới có `persistent_state_reused`.
- `creator_pod` và `created_at` trong file vẫn là lần đầu.

Pod không sở hữu lifetime PVC. Xóa Pod giữ PVC/PV. Xóa PVC với StorageClass có
`reclaimPolicy=Delete` sẽ xóa PV và backing data.

### Cleanup

```cmd
lab-4.4.bat cleanup
```

Cleanup này chủ đích xóa dữ liệu Lab 4.4, không đụng volume Kafka/Iceberg/MinIO.

**Câu chốt:** Pod là ephemeral, PVC là yêu cầu lưu trữ có lifecycle độc lập;
checksum và UID chứng minh hai vòng đời khác nhau.

[Tài liệu chi tiết Lab 4.4](./lab-4.4-persistent-volume-claims.md)

# Day 5 — Observability, Maintenance & Helm

<a id="lab-5-1"></a>

## Lab 5.1 — Self-Healing App

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** cấu hình HTTP liveness, file-based readiness và startup probe,
rồi gây lỗi có kiểm soát để kubelet tự restart container.

### Điều cần trình bày

Deployment `pipeline-self-healing` có:

- init container compile Java health server;
- `health-api` kiểm tra JAR, Flink, Iceberg, MinIO rồi tạo readiness file;
- `readiness-reporter` quan sát cùng `emptyDir` và đọc `/business`.

Ba probe giải quyết ba câu hỏi khác nhau:

| Probe | Câu hỏi | Khi thất bại |
|---|---|---|
| startup | Ứng dụng đã khởi động xong chưa? | Chưa chạy liveness/readiness; quá ngưỡng thì restart |
| readiness | Pod có nên nhận traffic không? | Rời Service endpoints, không restart |
| liveness | Process còn có khả năng tự phục hồi không? | Kubelet restart container |

Startup probe cho tối đa `2s × 20 = 40s` warm-up. Readiness dùng file
`/var/run/pipeline-health/ready`; liveness gọi HTTP `/live`.

### Demo nhanh

```cmd
lab-5.1.bat run
```

### Deploy và kiểm tra probes

```cmd
kubectl apply --dry-run=server -f .\lab-5.1-self-healing.yaml
kubectl apply -f .\lab-5.1-self-healing.yaml
kubectl rollout status deployment/pipeline-self-healing -n data-platform --timeout=180s
for /f %P in ('kubectl get pod -n data-platform -l lab=5.1 -o jsonpath^="{.items[0].metadata.name}"') do set "POD=%P"
echo POD=%POD%
```

```cmd
kubectl get pod %POD% -n data-platform
kubectl get pod %POD% -n data-platform -o jsonpath="{.spec.containers[?(@.name=='health-api')].startupProbe}{'\n'}"
kubectl get pod %POD% -n data-platform -o jsonpath="{.spec.containers[?(@.name=='health-api')].readinessProbe}{'\n'}"
kubectl get pod %POD% -n data-platform -o jsonpath="{.spec.containers[?(@.name=='health-api')].livenessProbe}{'\n'}"
kubectl exec %POD% -n data-platform -c health-api -- test -s /var/run/pipeline-health/ready
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- curl -fsS http://pipeline-self-healing:8080/business
```

Snapshot `/business` phải có JAR checksum, Flink jobs, Iceberg tables và MinIO
HTTP status thật.

### Gây liveness failure

Ghi nhận restart count:

```cmd
kubectl get pod %POD% -n data-platform -o jsonpath="{.status.containerStatuses[?(@.name=='health-api')].restartCount}{'\n'}"
kubectl exec %POD% -n data-platform -c health-api -- rm -f /var/run/pipeline-health/live
```

Theo dõi:

```cmd
kubectl get pod %POD% -n data-platform -w
```

Sau hai probe failure, `RESTARTS` tăng. Nhấn `Ctrl+C`, rồi:

```cmd
kubectl wait -n data-platform --for=condition=Ready pod/%POD% --timeout=120s
kubectl get pod %POD% -n data-platform
kubectl logs %POD% -n data-platform -c health-api --previous
kubectl get events -n data-platform --field-selector involvedObject.name=%POD% --sort-by=.metadata.creationTimestamp
```

Expected:

- liveness nhận HTTP 503 vì file `live` đã bị xóa;
- Event có `Unhealthy`, `Killing`, `Started`;
- chỉ `health-api` restart, Pod object và sidecar vẫn còn;
- container mới warm-up, audit dependency và tạo lại file readiness;
- `--previous` đọc log instance trước khi restart.

### Cleanup

```cmd
lab-5.1.bat cleanup
```

**Câu chốt:** readiness điều khiển traffic, liveness điều khiển restart, startup
bảo vệ tiến trình khởi động chậm khỏi bị liveness giết sớm.

[Tài liệu chi tiết Lab 5.1](./lab-5.1-self-healing.md)

---

<a id="lab-5-2"></a>

## Lab 5.2 — CLI Observability

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** dùng `logs -c`, `--previous`, Events và `kubectl top` để quan sát
workload thật.

### Điều cần trình bày

Lab tái sử dụng chính workload 5.1 vì nó có hai container, controlled restart,
Events và resource usage thật. Không tạo Pod chỉ để `echo` log giả.

### Demo nhanh

```cmd
lab-5.2.bat run
```

### Chuẩn bị workload và một restart

```cmd
lab-5.2.bat prepare
lab-5.2.bat restart
for /f %P in ('kubectl get pod -n data-platform -l lab=5.1 -o jsonpath^="{.items[0].metadata.name}"') do set "POD=%P"
echo POD=%POD%
```

Nếu làm hoàn toàn thủ công, có thể dùng lệnh xóa file `live` của Lab 5.1.

### Logs theo đúng container

```cmd
kubectl logs %POD% -n data-platform -c health-api --tail=20
kubectl logs %POD% -n data-platform -c readiness-reporter --tail=20
kubectl logs %POD% -n data-platform -c health-api --previous
```

`--previous` là log của container instance trước trong **cùng Pod**, không phải
log của Pod cũ thuộc ReplicaSet khác. Nếu container chưa từng restart, Kubernetes
sẽ báo không có previous terminated container.

Theo dõi live log khi cần:

```cmd
kubectl logs %POD% -n data-platform -c readiness-reporter -f
```

Nhấn `Ctrl+C` để dừng.

### Describe và Events

```cmd
kubectl describe pod %POD% -n data-platform
kubectl get events -n data-platform --field-selector involvedObject.name=%POD% --sort-by=.metadata.creationTimestamp
kubectl get events -n data-platform --field-selector type=Warning --sort-by=.metadata.creationTimestamp
```

Tìm `Unhealthy`, `Killing`, `Started`; đọc từ cuối phần `describe` trước rồi mới
đi sâu vào logs.

### Metrics

```cmd
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top pod %POD% -n data-platform --containers
kubectl top pods -n data-platform
kubectl top node
```

Nếu vừa tạo Pod hoặc Metrics Server, chờ một chu kỳ sample rồi chạy lại.
`kubectl top` không đọc resource requests/limits; nó đọc usage gần hiện tại từ
Metrics API.

Nếu thiếu Metrics API:

```cmd
kubectl apply -f .\lab-5.2-metrics-server.yaml
kubectl rollout status deployment/metrics-server -n kube-system --timeout=180s
kubectl top nodes
```

### Cleanup

```cmd
lab-5.2.bat cleanup
```

Chỉ gỡ Metrics Server nếu chính lab quản lý:

```cmd
lab-5.2.bat cleanup-metrics
```

**Câu chốt:** logs giải thích ứng dụng, Events giải thích quyết định của
Kubernetes, Metrics giải thích mức sử dụng tài nguyên; phải kết hợp cả ba.

[Tài liệu chi tiết Lab 5.2](./lab-5.2-cli-observability.md)

---

<a id="lab-5-3"></a>

## Lab 5.3 — Broken YAML Triage

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** sửa selector mismatch, invalid image name và Service targetPort
sai; phân biệt ba tầng lỗi.

### Ba checkpoint cần trình bày

| Lỗi | Tầng phát hiện | Hiện tượng |
|---|---|---|
| Deployment selector không match template | API admission | Apply bị từ chối, chưa có object |
| Image `INVALID@@TAG` | kubelet/container runtime | Pod tồn tại nhưng `InvalidImageName` |
| Service `targetPort: 9099`, app nghe 8080 | runtime network | Pod Ready, endpoint có address nhưng request lỗi |

API `TriageApi` cuối cùng gọi Flink `/jobs/overview` thật, nên response thành
công chứng minh toàn đường Pod → Service → dependency.

### Demo nhanh

```cmd
lab-5.3.bat run
```

### Lỗi 1 — selector mismatch

```cmd
lab-5.3.bat cleanup
kubectl apply --dry-run=server -f .\lab-5.3-broken.yaml
```

Lệnh **phải bị API server từ chối** với
`selector does not match template labels`.

```cmd
kubectl get deployment pipeline-triage -n data-platform
```

Expected `NotFound`: chưa có Deployment/Pod để xem logs.

### Lỗi 2 — invalid image

Apply source và checkpoint đã sửa selector:

```cmd
kubectl apply -f .\lab-5.3-app-source.yaml
kubectl apply -f .\lab-5.3-selector-fixed.yaml
kubectl get pods -n data-platform -l lab=5.3
kubectl describe pods -n data-platform -l lab=5.3
```

Pod phải hiện `InvalidImageName`; chuỗi image có hai ký tự `@` sai cú pháp.
Sửa trực tiếp:

```cmd
kubectl set image deployment/pipeline-triage -n data-platform gateway=mualanhlung017/ai-data-pipeline:1.0.2
kubectl rollout status deployment/pipeline-triage -n data-platform --timeout=180s
kubectl get pods -n data-platform -l lab=5.3
```

### Lỗi 3 — targetPort mismatch

Pod đã Ready nhưng Service gửi vào port 9099:

```cmd
kubectl get service pipeline-triage -n data-platform -o yaml
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-triage -o wide
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- curl -fsS --max-time 4 http://pipeline-triage:8080/api
```

Request trên **phải fail**. EndpointSlice có Pod IP không có nghĩa target port
đúng.

Patch về port ứng dụng 8080:

```cmd
kubectl patch service pipeline-triage -n data-platform --type=merge -p "{\"spec\":{\"ports\":[{\"name\":\"http\",\"port\":8080,\"protocol\":\"TCP\",\"targetPort\":8080}]}}"
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-triage -o wide
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- curl -fsS http://pipeline-triage:8080/api
```

Response phải có `component=pipeline-triage-api` và `flink_jobs=...`.

### Thứ tự triage CKAD

```text
1. kubectl apply --dry-run=server  -> API có nhận manifest?
2. kubectl get/describe pod       -> scheduler/kubelet/runtime ra sao?
3. kubectl logs -c                -> ứng dụng có chạy đúng?
4. kubectl get svc/endpointslice  -> selector và port có đúng?
5. curl từ trong cluster          -> data path có hoạt động?
```

Đừng bắt đầu bằng logs khi object còn chưa qua admission.

### Cleanup

```cmd
lab-5.3.bat cleanup
```

**Câu chốt:** cùng là “app không truy cập được” nhưng admission, runtime image
và network port để lại ba loại bằng chứng hoàn toàn khác nhau.

[Tài liệu chi tiết Lab 5.3](./lab-5.3-broken-yaml-triage.md)

---

<a id="lab-5-4"></a>

## Lab 5.4 — Helm Deploy & Rollback

**Thời lượng:** khoảng 45 phút<br>
**Mục tiêu:** lint/render chart, install với CLI overrides, upgrade bằng values
file và rollback release.

### Điều cần trình bày

Chart `lab-5.4-chart` deploy `pipeline-helm-auditor`. Mỗi replica audit JAR,
Flink, Iceberg và MinIO thật.

```text
Revision 1: stable, 1 replica, interval 15s
Revision 2: canary, 2 replicas, interval 5s
Revision 3: rollback content của revision 1
```

### Demo nhanh

```cmd
lab-5.4.bat run
```

### Kiểm tra Helm, lint và render

```cmd
helm version
helm list -A
helm lint .\lab-5.4-chart
helm template pipeline-helm .\lab-5.4-chart -n data-platform --set-string image.tag=1.0.2
```

`helm template` chỉ render YAML; chưa tạo release và chưa thay đổi cluster.

### Install revision 1

Đảm bảo release cũ không còn:

```cmd
helm uninstall pipeline-helm -n data-platform
```

Nếu Helm báo release not found thì bỏ qua và tiếp tục:

```cmd
helm install pipeline-helm .\lab-5.4-chart -n data-platform --set-string image.tag=1.0.2 --set replicaCount=1 --set releaseTrack=stable --wait --timeout 3m
helm status pipeline-helm -n data-platform
helm history pipeline-helm -n data-platform
kubectl get deployment pipeline-helm-auditor -n data-platform
kubectl get pods -n data-platform -l lab=5.4 -L release-track
kubectl logs -n data-platform deployment/pipeline-helm-auditor -c auditor --tail=20
```

Expected revision `1`, một replica, track `stable`, interval `15`.

### Upgrade revision 2

File `lab-5.4-upgrade-values.yaml` có:

```yaml
replicaCount: 2
releaseTrack: canary
auditIntervalSeconds: 5
```

```cmd
helm upgrade pipeline-helm .\lab-5.4-chart -n data-platform -f .\lab-5.4-upgrade-values.yaml --set-string image.tag=1.0.2 --wait --timeout 3m
helm history pipeline-helm -n data-platform
kubectl get deployment pipeline-helm-auditor -n data-platform
kubectl get pods -n data-platform -l lab=5.4 -L release-track
kubectl logs -n data-platform deployment/pipeline-helm-auditor -c auditor --tail=20
```

Expected revision `2`, hai replicas, track `canary`, interval `5`.

### Rollback

```cmd
helm rollback pipeline-helm 1 -n data-platform --wait --timeout 3m
helm history pipeline-helm -n data-platform
kubectl get deployment pipeline-helm-auditor -n data-platform
kubectl get pods -n data-platform -l lab=5.4 -L release-track
kubectl logs -n data-platform deployment/pipeline-helm-auditor -c auditor --tail=20
```

Rollback tạo release revision mới `3`; nó không xóa revision 2. Manifest của
revision 3 được phục hồi từ revision 1, nên:

```text
replicas=1
release-track=stable
AUDIT_INTERVAL_SECONDS=15
HELM_MANIFEST_REVISION=1
```

`helm history` nói current release revision là 3, trong khi env
`HELM_MANIFEST_REVISION=1` nằm trong manifest cũ được khôi phục. Hai số mô tả hai
khái niệm khác nhau.

Kiểm tra fields:

```cmd
kubectl get deployment pipeline-helm-auditor -n data-platform -o jsonpath="{.spec.replicas}{' track='}{.spec.template.metadata.labels.release-track}{' interval='}{.spec.template.spec.containers[0].env[?(@.name=='AUDIT_INTERVAL_SECONDS')].value}{' manifestRevision='}{.spec.template.spec.containers[0].env[?(@.name=='HELM_MANIFEST_REVISION')].value}{'\n'}"
```

### Cleanup

```cmd
lab-5.4.bat cleanup
```

Hoặc:

```cmd
helm uninstall pipeline-helm -n data-platform
```

**Câu chốt:** Helm release giữ lịch sử triển khai; upgrade tạo revision mới và
rollback cũng tạo revision mới chứa manifest được phục hồi.

[Tài liệu chi tiết Lab 5.4](./lab-5.4-helm-deploy-rollback.md)

---

# Phụ lục A — Kịch bản nói ngắn cho từng Day

## Day 1

“Day 1 trả lời câu hỏi workload được tạo và hoàn thành như thế nào. Pod là đơn
vị chạy; init/sidecar phân chia trách nhiệm; Job quản lý completion; CronJob
quản lý schedule; labels giúp chúng ta thao tác hàng loạt.”

## Day 2

“Day 2 trả lời cách phát hành cùng một nghiệp vụ. Rolling update thay dần Pod,
blue/green tách deploy khỏi traffic switch, HPA reconcile số replica từ metrics,
Kustomize tái sử dụng manifest giữa môi trường.”

## Day 3

“Day 3 tách config khỏi image và áp least privilege. Secret/ConfigMap cung cấp
dữ liệu chạy, SecurityContext giới hạn process, RBAC giới hạn Kubernetes API,
quota giới hạn ngân sách namespace.”

## Day 4

“Day 4 theo đường đi của request và dữ liệu. Service chọn endpoint bằng label,
Ingress route HTTP, NetworkPolicy giới hạn packet, PVC tách dữ liệu khỏi vòng
đời Pod.”

## Day 5

“Day 5 dùng health signals và bằng chứng vận hành. Probes giúp kubelet tự chữa,
logs/events/metrics giúp quan sát, triage đi từ admission đến network, Helm quản
lý lịch sử release.”

# Phụ lục B — Troubleshooting nhanh khi đang đứng lớp

## 1. Pod không chạy

```cmd
kubectl get pods -n data-platform -o wide
kubectl describe pod POD_NAME -n data-platform
kubectl get events -n data-platform --sort-by=.metadata.creationTimestamp
```

Đọc `STATUS`, container state, `Reason` và Events trước. Sau đó mới đọc log:

```cmd
kubectl logs POD_NAME -n data-platform -c CONTAINER_NAME
kubectl logs POD_NAME -n data-platform -c CONTAINER_NAME --previous
```

## 2. Image pull lỗi

```cmd
kubectl describe pod POD_NAME -n data-platform
kubectl get pod POD_NAME -n data-platform -o jsonpath="{.spec.containers[*].image}"
```

Phân biệt:

- `InvalidImageName`: image reference sai cú pháp, chưa pull.
- `ErrImagePull`/`ImagePullBackOff`: reference hợp lệ nhưng registry/tag/auth
  có vấn đề.

Project image ưu tiên:

```text
mualanhlung017/ai-data-pipeline:1.0.2
```

## 3. Service không truy cập được

```cmd
kubectl get service SERVICE_NAME -n data-platform -o yaml
kubectl get pods -n data-platform --show-labels
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=SERVICE_NAME -o wide
kubectl describe service SERVICE_NAME -n data-platform
```

Kiểm tra selector trước, rồi readiness, `port`, `targetPort` và NetworkPolicy.

## 4. Rollout bị kẹt

```cmd
kubectl rollout status deployment/DEPLOYMENT_NAME -n data-platform --timeout=30s
kubectl get rs,pods -n data-platform -l lab=X.Y
kubectl describe deployment DEPLOYMENT_NAME -n data-platform
kubectl rollout history deployment/DEPLOYMENT_NAME -n data-platform
```

## 5. HPA hiện `<unknown>`

```cmd
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -n data-platform
kubectl describe hpa HPA_NAME -n data-platform
kubectl get deployment DEPLOYMENT_NAME -n data-platform -o jsonpath="{.spec.template.spec.containers[*].resources.requests.cpu}"
```

HPA CPU utilization cần Metrics API và CPU requests.

## 6. Ingress trả 404/502

```cmd
kubectl get ingressclass
kubectl describe ingress pipeline-routing -n data-platform
kubectl get pods,service -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
kubectl get endpointslice -n data-platform
```

404 thường liên quan host/path/class; 502 thường liên quan Service endpoint hoặc
target port.

## 7. NetworkPolicy không chặn

```cmd
kubectl get networkpolicy -n data-platform
kubectl describe networkpolicy pipeline-backend-isolation -n data-platform
kubectl get pods -n data-platform --show-labels
kubectl get pods -n kube-system
```

Xác nhận policy selector chọn đúng backend và CNI có hỗ trợ enforcement.

## 8. PVC Pending

```cmd
kubectl get pvc -n data-platform
kubectl describe pvc pipeline-audit-state -n data-platform
kubectl get storageclass
kubectl get events -n data-platform --sort-by=.metadata.creationTimestamp
```

Với `WaitForFirstConsumer`, hãy tạo Pod dùng PVC trước khi kết luận provisioning
bị lỗi.

## 9. Helm command không tìm thấy

```cmd
"%LOCALAPPDATA%\Programs\Helm\helm.exe" version
```

Nếu lệnh trên chạy được, mở `cmd` mới để nhận User PATH.

# Phụ lục C — Cleanup toàn bộ resource lab

Chạy sau buổi học nếu muốn đưa cluster về chỉ còn stack project:

```cmd
lab-1.1.bat cleanup
lab-1.2.bat cleanup
lab-1.3.bat cleanup
lab-1.4.bat cleanup
lab-2.1.bat cleanup
lab-2.2.bat cleanup
lab-2.3.bat cleanup
lab-2.4.bat cleanup
lab-3.1.bat cleanup
lab-3.2.bat cleanup
lab-3.3.bat cleanup
lab-3.4.bat cleanup
lab-4.3.bat cleanup
lab-4.2.bat cleanup
lab-4.1.bat cleanup
lab-4.4.bat cleanup
lab-5.1.bat cleanup
lab-5.2.bat cleanup
lab-5.3.bat cleanup
lab-5.4.bat cleanup
```

Các add-on dùng chung được giữ lại theo mặc định. Chỉ dọn khi xác nhận runner
đã cài và không còn lab nào dùng:

```cmd
lab-2.3.bat cleanup-metrics
lab-5.2.bat cleanup-metrics
lab-4.2.bat cleanup-controller
```

Lưu ý dữ liệu:

- Lab 1.2 và 1.3 ghi record thật vào Kafka/Iceberg; cleanup Kubernetes resource
  không xóa các record đó.
- Lab 4.4 cleanup xóa PVC nên xóa snapshot của riêng bài 4.4.
- Không cleanup namespace `data-platform`.

# Phụ lục D — Checklist trước khi kết thúc buổi trình bày

```cmd
kubectl get deployment -n data-platform
kubectl get pods -n data-platform
kubectl get job,cronjob -n data-platform
kubectl get ingress,networkpolicy -n data-platform
kubectl get pvc -n data-platform
helm list -A
```

Checklist bằng lời:

- Tôi đã giải thích expected failure trước khi chạy chưa?
- Tôi đã chỉ ra bằng chứng từ API object, runtime và response nghiệp vụ chưa?
- Tôi đã phân biệt desired state với observed state chưa?
- Tôi đã cleanup đúng selector/tên resource của lab chưa?
- Tôi có giữ nguyên Kafka, Flink, Iceberg, MinIO và dữ liệu project không?

---

## Kết luận chung

Chuỗi lab đi từ một Pod imperative đến release lifecycle hoàn chỉnh. Điểm quan
trọng nhất không phải thuộc từng câu lệnh, mà là biết controller nào đang chịu
trách nhiệm và phải tìm bằng chứng ở đâu:

```text
Pod/kubelet        -> container state, probes, logs
Job controller     -> completion và retry
Deployment/HPA     -> rollout và replicas
Service/Ingress    -> selector, EndpointSlice và routing
CNI                -> NetworkPolicy enforcement
PV provisioner     -> PVC/PV binding và dữ liệu
API admission/RBAC -> validation, quota và authorization
Helm               -> release values, manifest và revision history
```

Khi demo, luôn kết thúc mỗi bài bằng một response, trạng thái hoặc checksum thật.
Đó là bằng chứng Kubernetes object không chỉ “apply thành công” mà nghiệp vụ
project thực sự hoạt động.
