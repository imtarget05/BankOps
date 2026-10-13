# Notes — plan finish-remaining (2026-10-13)

## Nguồn skill
- `/vibe-plan` yêu cầu đọc `Vide coding/superpowers/skills/writing-plans/SKILL.md` → **không đọc được**:
  - `Downloads/Vide coding` không tồn tại (đúng tên là `vibe-coding`).
  - `vibe-coding/superpowers` là symlink gãy → `~/.config/opencode/skills/superpowers` không tồn tại.
  - Skill tương đương `writing-plans` có ở `~/.config/opencode/skills/writing-plans` → đã load và dùng đúng format (header/task/verify/commit). Không bịa quy trình.

## Quyết định
1. Badge Duyệt đã có ở rail/topbar (agent song song) → plan chỉ thêm badge bottom-bar (Task B1), không làm trùng.
2. Ẩn menu theo role: fail-open, chỉ auditor thuần bị ẩn tab 3/4/5 (bảo toàn demo_checker + test cũ).
3. WP-C thêm `excel` + `printing` (~1-2MB build Web) — chấp nhận vì auditor cần file thật; CSV clipboard giữ làm fallback.
4. Timeline audit lọc client-side theo `ActivityEvent.subjectId`, không thêm API backend.
5. Critical path: Flutter SDK. Mọi task verify Flutter BLOCKED tới khi user cài SDK (Task A1).

## Tradeoff chưa chốt (cần user)
- Excel/PDF có đáng tăng size build Web không? Mặc định: có (đã plan WP-C).
