# Lab 4.2: Ingress Routing với frontend/backend thật

Thời lượng gợi ý: khoảng 60 phút. CKAD domain: Services and Networking.

## Mục tiêu

- Tạo Ingress `networking.k8s.io/v1`.
- Route `/` tới frontend Service.
- Route `/api` tới backend Service.
- Kiểm tra request thông qua endpoint của Ingress controller.

## Prerequisite quan trọng

Chỉ tạo Ingress object không tạo data plane. Cluster phải có Ingress controller.

Cluster local ban đầu chưa có controller. Batch runner cài manifest bare-metal được pin:

```text
ingress-nginx controller-v1.15.1
```

Ingress-nginx đã kết thúc bảo trì sau tháng 3/2026 và upstream khuyến cáo không triển khai mới trong production. Artifact cũ vẫn còn để dùng cho local training. Lab này dùng bản cuối cùng đã pin nhằm luyện CKAD Ingress API; không xem đây là lựa chọn production mới.

Nguồn chính thức:

- https://github.com/kubernetes/ingress-nginx
- https://kubernetes.github.io/ingress-nginx/deploy/
- https://kubernetes.io/docs/concepts/services-networking/ingress/

## Kiến trúc

Lab dùng lại frontend/backend của Lab 4.1:

```text
Ingress controller NodePort
  |
  |-- Prefix /api -> Service pipeline-backend:8080
  |                  -> LineNormalizer backend
  |
  `-- Prefix /    -> Service pipeline-frontend:8080
                     -> frontend
```

Rule `/api` được ưu tiên vì prefix dài hơn `/`.

Ingress không khai báo `host`, vì vậy rule match mọi Host header đi vào controller. Điều này tiện cho local lab bằng Node IP.

## Phần 0 — Chuẩn bị application

```cmd
lab-4.1.bat run
```

Backend Service phải có endpoints trước khi tạo Ingress:

```cmd
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-backend
kubectl get endpointslice -n data-platform -l kubernetes.io/service-name=pipeline-frontend
```

## Phần 1 — Cài controller cho local lab

Kiểm tra:

```cmd
kubectl get ingressclass
kubectl get deployment,service -n ingress-nginx
```

Nếu chưa có:

```cmd
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml
kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s
kubectl wait -n ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=180s
```

Bare-metal manifest expose controller bằng NodePort. Lấy port HTTP:

```cmd
kubectl get service ingress-nginx-controller -n ingress-nginx
kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath="{.spec.ports[0].nodePort}"
```

## Phần 2 — Apply Ingress

```cmd
kubectl apply --dry-run=server -f .\lab-4.2-ingress.yaml
kubectl apply -f .\lab-4.2-ingress.yaml
kubectl get ingress pipeline-routing -n data-platform
kubectl describe ingress pipeline-routing -n data-platform
```

`describe` phải hiển thị:

```text
/api -> pipeline-backend:8080
/    -> pipeline-frontend:8080
```

Bare-metal controller có thể để cột `ADDRESS` trống; routing vẫn hoạt động qua controller NodePort.

## Phần 3 — Verify `/`

Lấy Node IP và controller HTTP NodePort:

```cmd
kubectl get nodes -o wide
kubectl get service ingress-nginx-controller -n ingress-nginx
```

Ví dụ với Node IP `172.18.0.2` và NodePort thực tế:

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS http://172.18.0.2:NODE_PORT/
```

Expected:

```text
component=frontend
backend_service=http://pipeline-backend:8080/api
```

## Phần 4 — Verify `/api`

```cmd
kubectl exec -n data-platform deployment/flink-taskmanager -c taskmanager -- /usr/bin/curl -fsS "http://172.18.0.2:NODE_PORT/api?line=%20INGRESS%20DATA%20"
```

Expected:

```text
component=backend
normalized=ingress data
```

Không có `routed_by=frontend-service`: controller route `/api` trực tiếp tới backend, không đi qua frontend proxy.

## Troubleshooting

```cmd
kubectl get ingressclass
kubectl describe ingress pipeline-routing -n data-platform
kubectl get service,endpointslice -n data-platform
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100
```

Các lỗi thường gặp:

- không có Ingress controller;
- `ingressClassName` không match;
- Service không có EndpointSlice addresses;
- path hoặc service port sai;
- admission webhook chưa sẵn sàng ngay sau khi cài controller.

## Batch runner

```cmd
lab-4.2.bat run
lab-4.2.bat controller
lab-4.2.bat apply
lab-4.2.bat verify
lab-4.2.bat cleanup
lab-4.2.bat cleanup-controller
```

`cleanup` chỉ xóa Ingress. `cleanup-controller` chỉ gỡ controller nếu Deployment có annotation xác nhận do Lab 4.2 cài.

## Cleanup

```cmd
kubectl delete -f .\lab-4.2-ingress.yaml --ignore-not-found
```

Sau các bài networking:

```cmd
lab-4.1.bat cleanup
lab-4.2.bat cleanup-controller
```
