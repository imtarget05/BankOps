"""Bootstrap pytest cho toàn bộ test backend (`backend/tests/`).

Môi trường test chạy trên **dữ liệu demo** (user `demo_*` do `app.seed`
seed), vì vậy `APP_ENV` được set **TƯỜNG MINH** ở đây.

Vì sao phải set?
----------------
`app.config.Settings.app_env` mặc định là `production` (fail-closed): app
không set `APP_ENV` thì không được chạy ở chế độ demo (secret JWT phải do
env cấp, `assert_runtime_secrets` phải kích hoạt). Nếu test để mặc định,
`is_demo_mode` = False -> các đường tắt demo (OTP trả trong response, token
Google `mock-`, ...) bị chặn và phần lớn test fail với lý do lẫn lộn.

File này nằm ở `backend/` (không phải `backend/tests/`) để pytest nạp nó
TRƯỚC mọi conftest con và trước khi bất kỳ test module nào import `app.*`.
"""

import os

# Demo là **opt-in tường minh**: set ở đây để bộ test chạy ổn định trên dữ
# liệu seed sẵn có. Chạy production thì KHÔNG dùng file này.
os.environ.setdefault("APP_ENV", "demo")
os.environ.setdefault("DEMO_MODE", "true")
