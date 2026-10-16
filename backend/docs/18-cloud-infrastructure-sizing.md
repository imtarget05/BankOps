# 18 — Cloud Infrastructure Sizing & Cost Optimization (10–20 Users)

> **Mục tiêu**: Thiết kế hạ tầng Cloud đáp ứng đầy đủ tiêu chuẩn an ninh ngân hàng (BankOps), chịu lỗi cao (High Availability), tự phục hồi (Self-Healing) nhưng tối ưu hóa chi phí cho quy mô **10 - 20 người dùng nội bộ đồng thời** (Maker, Checker, Auditor).

---

## 1. Phân Tích Tải & Nhu Cầu Tài Nguyên (Workload Sizing)

Với 10 - 20 người dùng nghiệp vụ nội bộ tại các chi nhánh/quầy:
- **Tần suất thao tác**: Trung bình 1 giao dịch/người mỗi 1–3 phút.
- **Lưu lượng đỉnh (Peak RPS)**: 10 – 30 requests/giây (bao gồm cả server-sent events / polling trạng thái duyệt).
- **Kích thước dữ liệu**: Dữ liệu giao dịch, chứng từ mô phỏng, audit log hash SHA-256 tăng trưởng ~100MB – 500MB/tháng.
- **Yêu cầu quan trọng nhất**: Không phải khả năng scale hàng triệu request, mà là **tính toàn vẹn dữ liệu (Integrity)**, **tính bảo mật (Zero Trust/mTLS)** và **khả năng khôi phục khi sập (Disaster Recovery)**.

### Bảng Định Mức Tài Nguyên (Resource Quotas)

| Thành phần | Replicas | CPU Request | CPU Limit | RAM Request | RAM Limit | Lưu trữ Persistent |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **`bankops-frontend`** | 2 | 30m | 100m | 64Mi | 128Mi | N/A (Stateless) |
| **`bankops-api`** | 2 | 100m | 500m | 256Mi | 512Mi | N/A (Stateless) |
| **`bankops-worker`** | 1 | 50m | 300m | 128Mi | 256Mi | N/A (Stateless) |
| **`ingress-nginx`** | 1 | 50m | 200m | 128Mi | 256Mi | N/A |
| **`argocd-server`** | 1 | 50m | 200m | 128Mi | 256Mi | 2Gi (Config PVC) |
| **`postgresql-16`** | 1 Master | 250m | 1000m | 1Gi | 2Gi | 20Gi NVMe SSD |
| **Tổng tài nguyên cụm** | - | **~0.6 vCPU** | **~2.3 vCPU** | **~1.8 GB** | **~3.5 GB** | **~25 GB** |

> **Kết luận**: Một cụm Kubernetes gồm **2 Nodes (mỗi node 2 vCPU / 4GB RAM)** hoặc **1 Node chính 4 vCPU / 8GB RAM + Managed Database** là hoàn toàn dư tải (headroom > 60%) cho 10-20 người dùng hoạt động trơn tru.

---

## 2. So Sánh Các Phương Án Hạ Tầng & Ước Tính Chi Phí Hằng Tháng

### Phương án A: Managed Cloud Lean (Khuyến nghị cho tính tin cậy cao)
- **Nền tảng**: Google Cloud (GCP) hoặc DigitalOcean.
- **Compute**: GKE Autopilot (hoặc DigitalOcean DOKS 2 nodes 2vCPU/4GB).
- **Database**: Cloud SQL PostgreSQL 16 (`db-custom-1-3840` hoặc `db-g1-small`) có sẵn tính năng tự động sao lưu và PITR 7 ngày.
- **Object Storage**: Cloudflare R2 (Lưu trữ backup không tính phí egress).
- **Mạng & Bảo mật**: Cloudflare Free/Pro (WAF + DDoS + CDN + SSL).

| Hạng mục chi phí | GCP (USD/tháng) | DigitalOcean (USD/tháng) |
| :--- | :--- | :--- |
| Kubernetes Cluster Fee | $0 (GKE miễn phí cluster fee cho 1 cụm Autopilot) | $0 (DOKS miễn phí control plane) |
| Worker Nodes (Compute) | ~$25 - $35 (Chỉ trả tiền theo Pods chạy) | $48 (2 nodes × $24) |
| Managed PostgreSQL 16 | ~$35 - $45 (db-g1-small + 20GB SSD) | $20 (1 vCPU / 2GB RAM / 25GB SSD) |
| Ingress / Load Balancer | ~$18 (Cloud External LB) | $12 (DO Load Balancer) |
| Backup Storage (R2 / S3) | ~$1 - $2 | ~$1 - $2 |
| **Tổng cộng** | **~$79 - $100 / tháng** | **~$81 - $82 / tháng** |

---

### Phương án B: Siêu Tiết Kiệm (VPS K3s Lightweight Cluster)
- **Nền tảng**: Hetzner Cloud / Vultr / Linode.
- **Compute**: 2 Cloud VPS (Ví dụ Hetzner CX32: 4 vCPU, 8GB RAM, 80GB NVMe SSD ~€7.50/tháng/node).
- **K3s Cluster**: Node 1 làm Control Plane + Worker, Node 2 làm Worker + Backup Node.
- **Database**: PostgreSQL 16 chạy trong cụm K3s (Local NVMe PVC) kết hợp CronJob backup tự động lên Cloudflare R2 / AWS S3.
- **Tổng chi phí**: **~$18 - $30 / tháng**.

---

## 3. Kiến Trúc Mạng & Bảo Mật Chuẩn Ngân Hàng

1. **Zero Public Database**: Database PostgreSQL đặt hoàn toàn trong mạng riêng (Private Subnet / Cluster Network). Chỉ có các Pod `bankops-api` và `bankops-worker` trong namespace được phép kết nối qua NetworkPolicy.
2. **Reverse Proxy & WAF**: Toàn bộ lưu lượng truy cập từ ngoài Internet đi qua Cloudflare Edge (WAF, Anti-DDoS, Rate Limiting 100 req/min/IP).
3. **mTLS / IP Whitelisting**: Đối với chi nhánh ngân hàng, có thể cấu hình Cloudflare Access hoặc Ingress Whitelist dải IP tĩnh của văn phòng để ngăn chặn hoàn toàn truy cập trái phép từ bên ngoài.
4. **Least Privilege Pod Security**: Tất cả container chạy dưới quyền Non-root (`runAsUser: 10001`), Read-only root filesystem, drop toàn bộ Linux capabilities (`drop: [ALL]`).
