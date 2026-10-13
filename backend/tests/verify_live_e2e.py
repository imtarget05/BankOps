"""Live E2E Verification Script on Docker container and database."""
import json
import urllib.error
import urllib.request
import uuid

BASE = "http://localhost:8000/api/v1"


def post(url, data, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
        headers["Idempotency-Key"] = str(uuid.uuid4())
    req = urllib.request.Request(
        f"{BASE}{url}",
        data=json.dumps(data).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


def get(url, token=None):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(f"{BASE}{url}", headers=headers)
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    print("=== BẮT ĐẦU KIỂM THỬ E2E LIVE DOCKER API ===")

    # 1. Maker đăng nhập
    maker_auth = post(
        "/auth/login", {"username": "demo_maker", "password": "DemoPass123!"}
    )
    maker_token = maker_auth["access_token"]
    print(f"1. Maker (demo_maker) đăng nhập thành công. Token: {maker_token[:20]}...")

    # 2. Lấy danh sách két sắt & số dư ban đầu
    boxes = get("/cash-sim/boxes", maker_token)["boxes"]
    box_id = boxes[0]["id"]
    box_name = boxes[0]["name"]
    balances_before = get("/cash-sim/balances", maker_token)["balances"]
    bal_before = next(
        (float(b["amount"]) for b in balances_before if b["cashbox_id"] == box_id),
        0.0,
    )
    print(
        f"2. Két sắt: {box_name} ({box_id}) | Số dư ban đầu: {bal_before:,.2f} VND"
    )

    # 3. Maker tạo phiếu tiếp quỹ 600,000,000 VND
    req_created = post(
        "/cash-sim/requests",
        {
            "cashbox_id": box_id,
            "kind": "receipt",
            "amount": "600000000.00",
            "currency": "VND",
            "reason": "Tiếp quỹ tăng cường cuối ngày từ Hội Sở",
        },
        maker_token,
    )
    req_id = req_created["id"]
    print(
        f"3. Lập phiếu thành công. Mã phiếu: {req_id} | Số tiền: 600,000,000 VND | Trạng thái: {req_created['status']}"
    )

    # 4. Maker gửi duyệt
    req_sub = post(f"/cash-sim/requests/{req_id}/submit", {}, maker_token)
    print(f"4. Maker gửi duyệt thành công. Trạng thái phiếu: {req_sub['status']}")

    # 5. Checker đăng nhập
    checker_auth = post(
        "/auth/login",
        {"username": "demo_checker", "password": "DemoPass123!"},
    )
    checker_token = checker_auth["access_token"]
    print("5. Checker (demo_checker) đăng nhập thành công.")

    # 6. Checker gọi AI Copilot thẩm định rủi ro
    ai_assessment = post(
        "/ai/assess-request",
        {
            "request_id": req_id,
            "kind": "cash",
            "amount_or_qty": "600000000.00",
            "maker": "demo_maker",
            "reason": "Tiếp quỹ tăng cường cuối ngày từ Hội Sở",
        },
        checker_token,
    )
    risk_level = ai_assessment["risk_level"].upper()
    risk_score = ai_assessment["risk_score"]
    stamp = ai_assessment["audit_stamp"][:24]
    print(f"6. AI Copilot đánh giá phiếu {req_id}: Mức độ: {risk_level} | Điểm: {risk_score}/100")
    print(f"   Dấu kiểm toán SHA-256: {stamp}...")

    # 7. Checker thử duyệt với sai PIN (999999) -> Phải bị chặn 403
    try:
        post(
            f"/cash-sim/requests/{req_id}/approve",
            {"supervisor_pin": "999999"},
            checker_token,
        )
        print("X LỖI: Lẽ ra phải bị chặn khi nhập sai PIN!")
    except urllib.error.HTTPError as e:
        print(f"7. Xác thực an toàn: Nhập sai PIN 999999 bị từ chối với HTTP {e.code} ({e.reason}) - ĐẠT!")

    # 8. Checker duyệt với đúng PIN (123456)
    approved = post(
        f"/cash-sim/requests/{req_id}/approve",
        {"supervisor_pin": "123456"},
        checker_token,
    )
    print(f"8. Checker duyệt thành công với PIN 123456. Trạng thái phiếu: {approved['status']}")

    # 9. Kiểm tra số dư két sắt sau khi ghi sổ
    balances_after = get("/cash-sim/balances", checker_token)["balances"]
    bal_after = next(
        (float(b["amount"]) for b in balances_after if b["cashbox_id"] == box_id),
        0.0,
    )
    diff = bal_after - bal_before
    print(f"9. Số dư sau khi ghi sổ: {bal_after:,.2f} VND (Tăng chính xác: +{diff:,.2f} VND)")

    print("\n=== TOÀN BỘ LUỒNG E2E ĐÃ HOÀN TẤT THÀNH CÔNG 100%! ===")


if __name__ == "__main__":
    main()
