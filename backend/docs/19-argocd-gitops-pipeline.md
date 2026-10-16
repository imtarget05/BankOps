# 19 — Pipeline DevOps & GitOps Engine với ArgoCD

> **Mục tiêu**: Thiết lập quy trình phân phối phần mềm liên tục (CI/CD) hiện đại theo triết lý **GitOps**. Mã nguồn hạ tầng và ứng dụng được khai báo 100% trong Git, ArgoCD đảm bảo trạng thái thực tế trong Kubernetes Cluster luôn đồng bộ tuyệt đối với Git.

---

## 1. Triết Lý GitOps Cho BankOps

```text
[Developer Push Code]
        │
        ▼
[GitHub Actions CI] ──(Lint + Test + Build + Scan)──► [Container Registry: ghcr.io]
        │                                                     │
        ▼ (Update image tag commit)                           │ (Pull image)
[GitOps Manifests: infra/k8s/overlays/production]             │
        │                                                     │
        ▼ (Watch / Webhook)                                   ▼
   [ArgoCD Engine] ──(Reconcile & RollingUpdate)──► [Kubernetes Pods: Zero Downtime]
```

1. **Declarative**: Toàn bộ trạng thái cụm K8s (Deployments, Services, Ingress, CronJobs) được khai báo bằng YAML trong thư mục [`infra/k8s/`](file:///Users/mainguyenbinhtan/Downloads/BankOps/infra/k8s/).
2. **Versioned & Immutable**: Mỗi bản build container có tag cố định `:sha-<commit-hash>`, không bao giờ dùng `:latest` trên Production.
3. **Automated & Self-Healing**: Nếu ai đó dùng lệnh `kubectl` để sửa đổi hoặc xóa nhầm Pod/Service trên Cluster, ArgoCD sẽ phát hiện `OutOfSync` và tự động khôi phục (Self-Heal) về đúng trạng thái trên Git.
4. **Audit Trail**: Mọi thay đổi trên môi trường Production đều thể hiện qua Git commit history, có người review và phê duyệt (Pull Request).

---

## 2. Hướng Dẫn Cài Đặt ArgoCD Trên Cụm Kubernetes

### Bước 1: Cài đặt ArgoCD Core
```bash
# Tạo namespace riêng cho ArgoCD
kubectl create namespace argocd

# Cài đặt phiên bản ổn định mới nhất của ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Bước 2: Lấy mật khẩu đăng nhập ban đầu
```bash
# Mật khẩu mặc định của tài khoản 'admin'
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
```

### Bước 3: Mở giao diện Web ArgoCD UI
```bash
# Forward port ra máy quản trị (hoặc cấu hình Ingress)
kubectl port-forward svc/argocd-server -n argocd 8085:443
```
Truy cập: `https://localhost:8085` (User: `admin`, Password lấy ở Bước 2).

### Bước 4: Đăng ký ứng dụng BankOps vào ArgoCD
Áp dụng tệp cấu hình Application đã chuẩn bị sẵn trong repository:
```bash
kubectl apply -f infra/argocd/appproject.yaml
kubectl apply -f infra/argocd/bankops-application.yaml
```

---

## 3. Quy Trình Vận Hành CI/CD Tự Động

Pipeline được định nghĩa tại [`.github/workflows/ci-gitops.yml`](file:///Users/mainguyenbinhtan/Downloads/BankOps/.github/workflows/ci-gitops.yml):

1. **Giai đoạn Kiểm thử (Quality Gate)**:
   - Chạy `scripts/check_no_secrets.py` chống lộ khóa bí mật.
   - Kiểm tra chuẩn code: `ruff check backend/`.
   - Chạy kiểm thử tự động: `pytest` trên PostgreSQL container thật.
   - Kiểm tra giao diện Flutter: `flutter analyze` & `flutter test`.
2. **Giai đoạn Đóng gói (Container Build & Security Scan)**:
   - Build image backend (`bankops-api`) và frontend (`bankops-frontend`).
   - Đặt tag bất biến `:sha-${GITHUB_SHA::7}`.
   - Quét lỗ hổng bảo mật bằng **Trivy** trước khi đẩy lên GitHub Container Registry (`ghcr.io`).
3. **Giai đoạn GitOps (Manifest Auto-Update)**:
   - Workflow tự động cập nhật `newTag` trong [`infra/k8s/overlays/production/kustomization.yaml`](file:///Users/mainguyenbinhtan/Downloads/BankOps/infra/k8s/overlays/production/kustomization.yaml).
   - Commit với tiền tố `[skip ci]`.
   - ArgoCD tự động phát hiện commit mới trong vòng 60 giây và tiến hành deploy Rolling Update.

---

## 4. Quy Trình Rollback Tức Thì (Instant Rollback Runbook)

Khi phiên bản mới có lỗi nghiệp vụ trên Production, có 2 cách rollback:

### Cách 1: Git Revert (Khuyến nghị chuẩn GitOps)
```bash
# 1. Quay ngược commit gần nhất trên branch main
git revert HEAD -m "revert: rollback release to previous stable version"
git push origin main

# 2. ArgoCD lập tức nhận diện commit revert và đưa Pods trở lại image cũ trong 30 giây.
```

### Cách 2: Rollback Trực Tiếp Qua ArgoCD UI / CLI (Trường hợp khẩn cấp)
1. Truy cập ArgoCD UI $\rightarrow$ Chọn Application `bankops-production`.
2. Bấm vào nút **History and Rollback**.
3. Chọn phiên bản ID trước đó (Ví dụ `ID: 14`) $\rightarrow$ Bấm **Rollback**.
4. ArgoCD sẽ ghim phiên bản cũ và tạm dừng auto-sync cho đến khi GitOps repo được fix xong.
