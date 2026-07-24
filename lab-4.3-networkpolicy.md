# Lab 4.3: NetworkPolicy Isolation với frontend/backend

Thời lượng gợi ý: khoảng 45 phút. CKAD domain: Services and Networking.

## Mục tiêu

- Chỉ cho frontend Pods kết nối backend TCP `8080`.
- Chặn các Pod khác trong namespace truy cập backend.
- Chặn backend egress tới internet `0.0.0.0/0`.
- Vẫn cho backend query CoreDNS.
- Chứng minh bằng positive và negative tests trước/sau policy.

## Prerequisite

Lab dùng frontend/backend của Lab 4.1:

```cmd
lab-4.1.bat run
```

Cluster phải dùng CNI thực thi NetworkPolicy. Kindnet của cluster local hiện tích hợp `kube-network-policies`, vì vậy policy được enforce.

Kiểm tra CNI:

```cmd
kubectl get daemonset kindnet -n kube-system -o wide
kubectl get pods -n kube-system -l k8s-app=kindnet
```

## Policy chọn backend nào?

```yaml
podSelector:
  matchLabels:
    app: ai-data-pipeline
    lab: "4.1"
    component: normalizer-backend
policyTypes:
  - Ingress
  - Egress
```

Chỉ hai backend Pods bị isolate. Frontend không bị policy này select.

## Ingress allow-list

```yaml
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: ai-data-pipeline
            lab: "4.1"
            component: frontend
    ports:
      - protocol: TCP
        port: 8080
```

Vì không có `namespaceSelector`, `podSelector` ở `from` chỉ match frontend trong cùng namespace `data-platform`.

## Egress deny internet

NetworkPolicy chuẩn là allow-list; không có action `deny`. Khi một Pod được select cho Egress, mọi egress không match một allow rule đều bị chặn.

Policy chỉ allow backend gửi DNS tới CoreDNS:

```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: kube-system
        podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
      - protocol: TCP
        port: 53
```

Vì không có allow rule cho `0.0.0.0/0`, HTTP/HTTPS internet egress bị chặn. Response traffic cho một ingress connection được phép vẫn hoạt động.

## Phần 0 — Baseline trước policy

Xóa policy cũ:

```cmd
kubectl delete networkpolicy pipeline-backend-isolation -n data-platform --ignore-not-found
```

Frontend gọi backend:

```cmd
kubectl exec -n data-platform deployment/pipeline-frontend -c frontend -- /usr/bin/curl -fsS http://pipeline-backend:8080/api?line=frontend-baseline
```

Một Pod không phải frontend cũng gọi được:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://pipeline-backend:8080/api?line=unauthorized-baseline
```

Backend ra internet:

```cmd
kubectl exec -n data-platform deployment/pipeline-backend -c backend -- /usr/bin/curl -fsS --max-time 10 https://example.com
```

Ba lệnh phải thành công để baseline có ý nghĩa.

## Phần 1 — Apply policy

```cmd
kubectl apply --dry-run=server -f .\lab-4.3-networkpolicy.yaml
kubectl apply -f .\lab-4.3-networkpolicy.yaml
kubectl describe networkpolicy pipeline-backend-isolation -n data-platform
```

## Phần 2 — Positive test

Frontend vẫn gọi backend được:

```cmd
kubectl exec -n data-platform deployment/pipeline-frontend -c frontend -- /usr/bin/curl -fsS --max-time 5 http://pipeline-backend:8080/api?line=frontend-allowed
```

Expected có:

```text
component=backend
normalized=frontend-allowed
```

Frontend Service proxy cũng vẫn hoạt động:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 5 http://pipeline-frontend:8080/api?line=proxy-allowed
```

Flink Pod chỉ gọi frontend; kết nối backend tiếp theo phát ra từ frontend Pod nên được allow.

## Phần 3 — Negative ingress test

Flink Pod gọi thẳng backend:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS --max-time 3 http://pipeline-backend:8080/api?line=must-be-denied
```

Lệnh phải timeout/fail. Backend Service và EndpointSlices vẫn tồn tại; traffic bị CNI chặn sau khi Service chọn endpoint.

## Phần 4 — Negative egress test

DNS vẫn hoạt động:

```cmd
kubectl exec -n data-platform deployment/pipeline-backend -c backend -- getent hosts example.com
```

HTTPS internet phải fail:

```cmd
kubectl exec -n data-platform deployment/pipeline-backend -c backend -- /usr/bin/curl -fsS --max-time 3 https://example.com
```

Nếu CNI không support NetworkPolicy, negative tests sẽ thành công ngoài dự kiến. API server vẫn nhận NetworkPolicy object nhưng không tự enforce packet filtering.

## Ảnh hưởng tới Ingress Lab 4.2

Ingress controller nằm ở namespace `ingress-nginx`, không mang label frontend. Sau khi policy này được apply, route `/api` trực tiếp từ controller tới backend sẽ bị chặn đúng theo yêu cầu “frontend -> backend only”. Route `/` tới frontend vẫn hoạt động; frontend proxy `/api` vẫn được phép.

## Batch runner

```cmd
lab-4.3.bat run
lab-4.3.bat baseline
lab-4.3.bat apply
lab-4.3.bat verify
lab-4.3.bat cleanup
```

## Cleanup

```cmd
kubectl delete -f .\lab-4.3-networkpolicy.yaml --ignore-not-found
```

Sau cleanup, direct backend access và internet egress được khôi phục.
