# TÀI LIỆU ĐẶC TẢ YÊU CẦU PHẦN MỀM (SRS)
# ỨNG DỤNG QUẢN LÝ NHẬP XUẤT TỒN QUÁN TRÀ SỮA
*(Chuẩn hóa chi tiết bám sát 100% theo bản mô tả nghiệp vụ của Khách hàng)*

---

## 1. TỔNG QUAN HỆ THỐNG
* **Mục tiêu ứng dụng:** Số hóa toàn diện quy trình kiểm hàng hằng ngày tại quán trà sữa, thay thế hoàn toàn các bảng tính Excel và sổ sách thủ công.
* **Giá trị mang lại:**
  * Theo dõi chính xác lượng nguyên vật liệu luân chuyển theo từng ca làm việc (Ca Sáng, Ca Chiều, Ca Lỡ ngày).
  * Giảm thiểu thất thoát nguyên vật liệu tại quầy pha chế.
  * Kiểm soát định mức tiêu hao nguyên vật liệu qua từng ca.
  * Tự động hóa quy trình cảnh báo đặt hàng và cảnh báo chênh lệch tồn kho.

---

## 2. PHÂN QUYỀN NGƯỜI DÙNG (USER ROLES)

Hệ thống thiết lập 2 nhóm quyền người dùng theo đúng yêu cầu:

### 2.1. Quản lý (Admin / Manager)
* **Quyền hạn toàn hệ thống:**
  * Thiết lập và quản lý danh mục nguyên vật liệu, nhóm hàng, quy cách đóng gói.
  * Cài đặt định mức tồn kho an toàn (Min / Max) cho từng mặt hàng.
  * Quản lý danh sách tài khoản nhân viên và phân quyền.
  * Xem toàn bộ hệ thống báo cáo xuất nhập tồn tổng hợp, biểu đồ tiêu hao, lịch sử kiểm kê theo ca và nhân viên.
  * Tiếp nhận thông báo đẩy (push notification) khi tồn kho chạm ngưỡng an toàn hoặc có chênh lệch kiểm kê.
  * Xét duyệt các **"Phiếu nhập/xuất điều chỉnh"** và **"Phiếu điều chỉnh kiểm kê"**.

### 2.2. Nhân viên pha chế / Trưởng ca (Staff)
* **Quyền hạn thao tác tại quầy:**
  * Đăng nhập tài khoản tại quầy pha chế (trên Mobile App / Tablet).
  * Ghi nhận hàng nhập phát sinh trong ca làm việc.
  * Nhập liệu số lượng nguyên vật liệu sử dụng (tiêu hao / chế biến) trong ca.
  * Thực hiện kiểm đếm và chốt tồn cuối ca.
  * Gửi báo cáo hư hỏng nguyên vật liệu phát sinh trong ca.
  * Tạo yêu cầu "Phiếu điều chỉnh kiểm kê" gửi Quản lý duyệt khi cần sửa đổi số liệu đã khóa.

---

## 3. YÊU CẦU CHỨC NĂNG CHI TIẾT (FUNCTIONAL REQUIREMENTS)

### 3.1. Quản lý danh mục nguyên vật liệu
* **Phân loại theo nhóm nghiệp vụ:**
  * Nhóm Trà (Trà đen, Trà xanh, Trà Ô long, Trà lài...).
  * Nhóm Bột & Sữa (Bột kem béo, Sữa tươi, Sữa đặc, Bột matcha, Bột socola...).
  * Nhóm Topping (Trân châu đen, Trân châu trắng, Thạch nha đam, Thạch dừa, Pudding...).
  * Nhóm Syrup & Mứt (Syrup đào, Syrup dâu, Mứt xoài, Đường nước...).
  * Nhóm Bao bì & Vật dụng tiêu hao (Ly nhựa, Màng ép ly, Ống hút, Muỗng, Túi mang về).
* **Thông tin chi tiết từng mã hàng:**
  * Mã nguyên liệu (SKU/Code).
  * Tên nguyên liệu.
  * Đơn vị tính cơ bản (Gói, Túi, Kg, Hộp, Viên, Chai, Lon...).
  * Quy cách đóng gói (Ví dụ: Thùng 20 gói, Hộp 1 Lít, Bao 25kg, Bịch 100 cái).
* **Định mức tồn kho an toàn (Min / Max):**
  * Thiết lập số lượng tồn tối thiểu (`Min Stock`) cho từng mặt hàng (ví dụ: Trà đen tối thiểu 30 gói, Sữa tươi tối thiểu 10 hộp). Khi tồn cuối ngày rơi xuống dưới hoặc bằng mức này, hệ thống tự động kích hoạt cảnh báo.
  * Thiết lập số lượng tồn tối đa (`Max Stock`) để kiểm soát không nhập dư thừa.

---

### 3.2. Quản lý Nhập kho
* **Tạo phiếu nhập kho:**
  * Nhân viên hoặc Quản lý tạo phiếu khi nhận hàng giao từ Nhà cung cấp hoặc từ Kho trung tâm.
* **Các trường thông tin bắt buộc trên phiếu nhập:**
  * Ngày giờ nhập hàng.
  * Nhà cung cấp / Nguồn giao hàng.
  * Mã và tên nguyên liệu nhập.
  * Số lượng nhập.
  * Đơn vị tính.
  * Đơn giá nhập và thành tiền.
  * Số lô sản xuất (Lot Number).
  * Hạn sử dụng (Expiry Date).
* **Cơ chế cập nhật tồn kho:**
  * Số lượng nhập kho được tự động cộng dồn vào **Tồn đầu ngày** (nếu nhập trước giờ mở quầy) hoặc cộng trực tiếp vào trường **"Nhập hàng"** tại thời điểm nhập trong ca đang diễn ra.

---

### 3.3. Quản lý xuất kho và theo dõi tiêu hao theo ca
* **Thiết kế giao diện kiểm hàng theo thời gian thực tế chia làm 3 ca:**
  1. **Ca Sáng:** Từ `07:30` đến `15:00`
  2. **Ca Chiều:** Từ `15:00` đến `23:00`
  3. **Ca Lỡ ngày:** Từ `07:30` đến `18:00` (dành cho nhân viên làm ca lỡ tăng cường)
* **Màn hình nhập liệu kiểm hàng hiển thị đầy đủ các trường thông tin:**
  * **Tồn đầu ca:** Hệ thống tự động trích xuất số liệu từ **Tồn cuối của ca liền trước** (hoặc Tồn cuối ngày hôm trước nếu là ca mở cửa sáng).
  * **Nhập hàng:** Khối lượng/số lượng nguyên liệu nhận thêm ngay trong ca làm việc (tự động tổng hợp từ các phiếu nhập hàng phát sinh trong khung giờ của ca).
  * **Sử dụng:** Số lượng nguyên liệu đã tiêu hao hoặc chế biến trong ca (nhân viên nhập liệu trực tiếp).
  * **Còn lại cuối ca (Tồn lý thuyết):** Hệ thống tự động tính toán chính xác theo công thức:
    $$\text{Còn lại cuối ca} = (\text{Tồn đầu ca} + \text{Nhập hàng}) - \text{Sử dụng}$$
  * **Kiểm kê thực tế:** Trường nhập liệu để nhân viên điền số lượng đếm được thực tế tại quầy vào cuối ca.
  * **Độ lệch (Chênh lệch):** Hệ thống tự động tính toán và hiển thị:
    $$\text{Độ lệch} = \text{Kiểm kê thực tế} - \text{Còn lại cuối ca}$$

---

### 3.4. Hệ thống cảnh báo tự động
* **Cảnh báo tồn kho thấp:**
  * Tự động **highlight đổi màu đỏ (nền hoặc chữ)** trên giao diện màn hình kiểm hàng đối với các mặt hàng có số lượng Còn lại cuối ngày chạm hoặc rơi xuống dưới định mức an toàn (Ví dụ: Trà xanh < 30 gói).
  * Đồng thời gửi **thông báo đẩy (Push Notification)** tức thời đến thiết bị của Quản lý để kịp thời lên đơn đặt hàng mới.
* **Cảnh báo chênh lệch kiểm kê:**
  * Báo động cảnh báo trực quan ngay trên màn hình nếu số lượng tồn lý thuyết trên phần mềm không khớp với số đếm kiểm kê thực tế cuối ca của nhân viên (`Độ lệch khác 0`).
  * Yêu cầu nhân viên kiểm đếm lại hoặc xác nhận độ lệch trước khi hoàn tất chốt ca.
* **Cảnh báo cận date (Cận hạn sử dụng):**
  * Tự động quét và hiển thị thông báo nhắc nhở đối với các nguyên liệu có hạn sử dụng ngắn (như sữa tươi thanh trùng, trái cây tươi, pudding, trân châu đã chế biến).
  * Phân loại mức độ: Cận date vàng (nhắc nhở ưu tiên dùng trước) và Cận date đỏ (hết hạn trong ngày/đã hết hạn).

---

### 3.5. Hệ thống Báo cáo (Dashboards)
* **Báo cáo Xuất - Nhập - Tồn tổng hợp:**
  * Trình bày dưới dạng **bảng lưới (Data Grid)** chi tiết từng mặt hàng.
  * Bộ lọc linh hoạt theo thời gian: **Ngày**, **Tuần**, **Tháng**, hoặc khoảng ngày tùy chọn.
  * Cung cấp đầy đủ các cột: Tồn đầu kỳ, Tổng nhập, Tổng sử dụng/tiêu hao, Tồn cuối kỳ, Tổng độ lệch kiểm kê.
* **Biểu đồ phân tích tiêu hao:**
  * Biểu đồ trực quan xếp hạng **Top nguyên liệu tiêu hao nhiều nhất** trong ngày/tuần/tháng giúp Quản lý nắm bắt xu hướng tiêu dùng và chuẩn bị nguồn hàng.
* **Lịch sử đối chiếu kiểm kê ca chi tiết:**
  * Bảng đối chiếu chi tiết lịch sử kiểm kê giữa Ca Sáng, Ca Chiều, Ca Lỡ ngày.
  * Ghi nhận định danh chi tiết đến **từng nhân viên / trưởng ca** thực hiện chốt số liệu (tên nhân viên, thời gian chốt, số liệu nhập, độ lệch phát sinh).

---

## 4. YÊU CẦU PHI CHỨC NĂNG (NON-FUNCTIONAL REQUIREMENTS)

### 4.1. Đa nền tảng (Cross-platform)
* **Giao diện Front-end quầy (Mobile App / Tablet):**
  * Thiết kế thân thiện tối ưu cho màn hình cảm ứng (Touch-friendly).
  * Các nút bấm kích thước lớn, dễ bấm bằng một tay, khoảng cách rõ ràng để nhân viên pha chế dễ dàng thao tác nhanh trực tiếp tại quầy trong lúc làm việc.
* **Giao diện Web Dashboard Quản trị:**
  * Thiết kế dạng bảng điều khiển chuyên sâu (Admin Dashboard) dành riêng cho Quản lý trên máy tính/trình duyệt web.
  * Hỗ trợ xem biểu đồ phân tích, bảng lưới dữ liệu lớn, quản lý danh mục và duyệt phiếu nhanh chóng.

### 4.2. Khả năng ngoại tuyến (Offline Mode)
* Cho phép nhân viên nhập liệu số kiểm kê cuối ca ngay cả khi mất kết nối mạng Internet hoặc mạng Wifi tại quầy bị chập chờn.
* Dữ liệu nhập được lưu trữ an toàn trong bộ nhớ cục bộ của thiết bị.
* Hệ thống tự động đồng bộ (Auto Sync) toàn bộ dữ liệu lên máy chủ ngay khi thiết bị có kết nối Internet trở lại mà không làm mất mát số liệu.

### 4.3. Tính toàn vẹn dữ liệu (Data Integrity & Lock)
* **Khóa cứng tự động:** Dữ liệu chốt ca sau khoảng thời gian quy định sẽ tự động khóa cứng (Read-only / Locked).
* **Chống sửa đổi tùy tiện:** Nhân viên không được quyền tự ý sửa đổi số liệu đã chốt trong quá khứ.
* **Quy trình điều chỉnh:** Mọi thay đổi, bổ sung sau khi ca đã khóa bắt buộc phải thông qua lệnh tạo **"Phiếu điều chỉnh kiểm kê"**, ghi rõ nguyên nhân và phải được **Quản lý phê duyệt** thì số liệu mới được cập nhật.

---

## 5. LUỒNG NGHIỆP VỤ CỐT LÕI (USER FLOW)

Hệ thống vận hành theo đúng quy trình tuần tự khép kín giữa các ca trong ngày:

```mermaid
sequenceDiagram
    autonumber
    actor TCS as Trưởng Ca Sáng (07:30 - 15:00)
    actor NVL as Nhân viên Ca Lỡ (07:30 - 18:00)
    actor TCC as Trưởng Ca Chiều (15:00 - 23:00)
    participant APP as Ứng dụng Quầy (Mobile/Tablet)
    actor QL as Quản lý (Web/Push Alert)

    Note over TCS,APP: 1. Mở ca đầu ngày (07:30)
    TCS->>APP: Đăng nhập quầy -> Kiểm tra chốt số "Tồn đầu ca sáng" (khớp với Tồn cuối ngày hôm trước)
    
    Note over TCS,NVL,APP: 2. Vận hành trong ca
    opt Có giao hàng trong ca
        TCS->>APP: Ghi nhận phiếu hàng nhập thêm
    end
    
    Note over TCS,APP: 3. Kết thúc Ca Sáng (15:00)
    TCS->>APP: Nhập số lượng "Sử dụng" trong ca
    APP->>APP: Tự động tính Còn lại cuối ca = (Tồn đầu + Nhập) - Sử dụng
    TCS->>APP: Nhập số lượng "Kiểm kê thực tế"
    APP->>APP: Đối chiếu độ lệch, cảnh báo trên màn hình nếu lệch
    TCS->>APP: Xác nhận chốt số "Tồn cuối ca sáng"

    Note over TCC,APP: 4. Bàn giao sang Ca Chiều (15:00)
    TCC->>APP: Đăng nhập nhận bàn giao -> "Tồn đầu ca chiều" tự động hiển thị từ "Tồn cuối ca sáng"
    
    opt Kết thúc Ca Lỡ ngày (18:00)
        NVL->>APP: Ghi nhận số liệu nhập/sử dụng phát sinh trong ca lỡ
    end

    Note over TCC,QL: 5. Đóng ca cuối ngày (23:00)
    TCC->>APP: Nhập "Sử dụng" và đếm "Kiểm kê thực tế" cuối ca chiều
    TCC->>APP: Xác nhận chốt "Tồn cuối ca chiều"
    APP->>APP: Tự động lưu trữ mốc "Còn lại cuối ngày"
    alt Có mặt hàng <= Định mức an toàn (Min Stock)
        APP->>APP: Tự động highlight đổi màu đỏ nền/chữ
        APP-->>QL: Gửi thông báo đẩy (Push Notification) cảnh báo tồn kho thấp
    end
    APP-->>QL: Tự động kết xuất báo cáo gửi đến thiết bị của Quản lý
```

---

## 6. CHI TIẾT MÀN HÌNH NHẬP LIỆU KIỂM KÊ THEO CA (UI SPECIFICATION)

Để lập trình giao diện quầy chính xác theo mục 3.3, màn hình kiểm kê ca bao gồm bảng nhập liệu với các cột:

| STT | Tên nguyên vật liệu | Đơn vị tính | Tồn đầu ca *(Tự động)* | Nhập hàng *(Tự động / Phiếu)* | Sử dụng *(Nhân viên nhập)* | Còn lại cuối ca *(Hệ thống tính)* | Kiểm kê thực tế *(Nhân viên nhập)* | Độ lệch *(Hệ thống tính)* | Cảnh báo trạng thái |
| :---: | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| 1 | Trà đen số 9 | Gói | 50 | 20 | 25 | **45** | **45** | 0 | 🟢 Khớp |
| 2 | Bột kem béo B-One | Túi | 20 | 0 | 8 | **12** | **10** | **-2** | 🔴 Lệch cảnh báo |
| 3 | Sữa tươi tiệt trùng | Hộp | 15 | 10 | 12 | **13** | **13** | 0 | 🟢 Khớp |
| 4 | Trân châu đen Gia Uy | Gói | 35 | 0 | 10 | **25** | **25** | 0 | 🔴 Tồn < Min (30) |

* **Quy tắc hiển thị màu:**
  * Cột **Độ lệch khác 0**: Highlight nền vàng/chữ đỏ cảnh báo nhân viên kiểm kê lại.
  * Cột **Tồn chạm hoặc dưới Min**: Tự động chuyển toàn bộ dòng thành nền đỏ hoặc chữ đỏ để kích hoạt cảnh báo đặt hàng.
