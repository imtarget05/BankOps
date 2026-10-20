"""STEP 5 — IP client sau reverse proxy phải lấy AN TOÀN (fail-closed).

Residual: rate-limit dùng `request.client.host` (không đọc `X-Forwarded-For`
để tránh giả mạo) -> sau nginx/Cloudflare, MỌI request cùng 1 IP của proxy
=> khoá theo IP vô hiệu. Nhưng đọc `X-Forwarded-For` mù quáng thì client tự
giả mạo IP để né rate-limit.

Quy tắc (xem `app/api/routes/auth_utils.py::client_ip`):
- KHÔNG cấu hình proxy đáng tin -> bỏ qua `X-Forwarded-For`, dùng IP peer.
- `TRUSTED_PROXY_COUNT=N` -> chỉ tin XFF khi chuỗi đủ N hop; IP client là hop
  thứ `len(hops) - N`.
- `TRUSTED_PROXY_IPS` -> chỉ tin XFF khi IP peer nằm trong danh sách; IP lấy là
  hop gần nhất KHÔNG thuộc danh sách proxy.
"""
from __future__ import annotations

from app.api.routes.auth_utils import client_ip


class _FakeClient:
    def __init__(self, host: str):
        self.host = host


class _FakeRequest:
    def __init__(self, peer: str, xff: str | None = None):
        self.client = _FakeClient(peer)
        self.headers = {}
        if xff is not None:
            self.headers["x-forwarded-for"] = xff


def test_without_trusted_proxy_config_xff_is_ignored(monkeypatch):
    """Mặc định KHÔNG tin header -> IP lấy từ kết nối thật."""
    monkeypatch.delenv("TRUSTED_PROXY_IPS", raising=False)
    monkeypatch.delenv("TRUSTED_PROXY_COUNT", raising=False)
    req = _FakeRequest("10.0.0.1", "203.0.113.7, 198.51.100.2")
    assert client_ip(req) == "10.0.0.1", (
        "không cấu hình proxy đáng tin thì PHẢI bỏ qua X-Forwarded-For "
        "(client có thể tự gửi header để giả mạo IP)"
    )


def test_trusted_proxy_count_resolves_real_client_ip(monkeypatch):
    """`TRUSTED_PROXY_COUNT=1` -> IP client là hop gần nhất trong XFF."""
    monkeypatch.delenv("TRUSTED_PROXY_IPS", raising=False)
    monkeypatch.setenv("TRUSTED_PROXY_COUNT", "1")
    # client 203.0.113.7 -> proxy 198.51.100.2 -> app
    req = _FakeRequest("198.51.100.2", "203.0.113.7")
    assert client_ip(req) == "203.0.113.7"


def test_trusted_proxy_count_two_hops(monkeypatch):
    """`TRUSTED_PROXY_COUNT=2` -> bỏ qua 2 hop proxy, lấy IP client thật."""
    monkeypatch.delenv("TRUSTED_PROXY_IPS", raising=False)
    monkeypatch.setenv("TRUSTED_PROXY_COUNT", "2")
    # client -> p1 -> p2 -> app ; XFF = "client, p1"
    req = _FakeRequest("192.0.2.9", "203.0.113.7, 198.51.100.2")
    assert client_ip(req) == "203.0.113.7"


def test_trusted_proxy_count_requires_enough_hops(monkeypatch):
    """Chuỗi XFF không đủ hop -> fail-closed, giữ IP peer."""
    monkeypatch.delenv("TRUSTED_PROXY_IPS", raising=False)
    monkeypatch.setenv("TRUSTED_PROXY_COUNT", "3")
    req = _FakeRequest("192.0.2.9", "203.0.113.7")
    assert client_ip(req) == "192.0.2.9", (
        "không xác minh được chuỗi proxy thì KHÔNG được tin XFF"
    )


def test_trusted_proxy_ips_list(monkeypatch):
    """`TRUSTED_PROXY_IPS` -> chỉ tin XFF khi peer là proxy đáng tin."""
    monkeypatch.delenv("TRUSTED_PROXY_COUNT", raising=False)
    monkeypatch.setenv("TRUSTED_PROXY_IPS", "10.0.0.1,10.0.0.2")
    req = _FakeRequest("10.0.0.1", "203.0.113.7, 198.51.100.2")
    assert client_ip(req) == "198.51.100.2", (
        "hop gần nhất KHÔNG phải proxy đáng tin -> đó là IP client thật"
    )


def test_trusted_proxy_ips_peer_not_trusted_ignores_xff(monkeypatch):
    """Peer KHÔNG nằm trong danh sách proxy -> bỏ qua XFF (chống giả mạo)."""
    monkeypatch.delenv("TRUSTED_PROXY_COUNT", raising=False)
    monkeypatch.setenv("TRUSTED_PROXY_IPS", "10.0.0.1")
    req = _FakeRequest("203.0.113.66", "203.0.113.7, 198.51.100.2")
    assert client_ip(req) == "203.0.113.66"


def test_trusted_proxy_ips_supports_cidr(monkeypatch):
    """Danh sách proxy nhận cả CIDR."""
    monkeypatch.delenv("TRUSTED_PROXY_COUNT", raising=False)
    monkeypatch.setenv("TRUSTED_PROXY_IPS", "10.0.0.0/24")
    req = _FakeRequest("10.0.0.5", "203.0.113.7")
    assert client_ip(req) == "203.0.113.7"


def test_no_xff_header_falls_back_to_peer(monkeypatch):
    """Không có header -> IP peer."""
    monkeypatch.setenv("TRUSTED_PROXY_COUNT", "1")
    req = _FakeRequest("192.0.2.9")
    assert client_ip(req) == "192.0.2.9"


def test_request_without_client_falls_back_to_unknown(monkeypatch):
    """Request không có `client` -> 'unknown' (không crash)."""
    monkeypatch.delenv("TRUSTED_PROXY_IPS", raising=False)
    monkeypatch.delenv("TRUSTED_PROXY_COUNT", raising=False)
    assert client_ip(None) == "unknown"
