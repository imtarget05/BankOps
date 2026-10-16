"""Tea receipt lot/expiry + single-open shift guard.

Revision ID: 017_tea_receipt_lot_expiry
Revises: 016_shift_stocktake_fields
"""
import sqlalchemy as sa

from alembic import op

revision = "017_tea_receipt_lot_expiry"
down_revision = "016_shift_stocktake_fields"
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    req_cols = {c["name"] for c in sa.inspect(bind).get_columns("inv_requests")}
    if "supplier" not in req_cols:
        op.add_column("inv_requests", sa.Column("supplier", sa.String(256), nullable=True))
    if "received_at" not in req_cols:
        op.add_column("inv_requests", sa.Column("received_at", sa.DateTime(timezone=True), nullable=True))
    line_cols = {c["name"] for c in sa.inspect(bind).get_columns("inv_request_lines")}
    if "unit_price" not in line_cols:
        op.add_column("inv_request_lines", sa.Column("unit_price", sa.Numeric(20, 2), nullable=True))
    if "lot_no" not in line_cols:
        op.add_column("inv_request_lines", sa.Column("lot_no", sa.String(64), nullable=True))
    if "expiry_date" not in line_cols:
        op.add_column("inv_request_lines", sa.Column("expiry_date", sa.Date(), nullable=True))
    # Không xoá catalogue/dữ liệu lịch sử khi migrate. Các item cũ có thể đã
    # được tham chiếu bởi tài sản, phiếu hoặc movement; dọn dữ liệu phải là
    # thao tác quản trị có chủ đích, không được làm migration khởi động lỗi.
    # Giữ đợt kiểm kê mở mới nhất nếu dữ liệu cũ đã có các bản ghi trùng; các
    # bản còn lại được đóng để có thể áp dụng bất biến "một ca chỉ có một đợt
    # kiểm kê mở" mà không xoá chứng từ lịch sử.
    op.execute(
        "WITH ranked AS ("
        " SELECT id, ROW_NUMBER() OVER ("
        "   PARTITION BY location_id, business_date,"
        "     COALESCE(NULLIF(shift_code, ''), 'none')"
        "   ORDER BY created_at DESC, id DESC"
        " ) AS rn"
        " FROM inv_stocktakes WHERE status = 'open'"
        ") UPDATE inv_stocktakes AS stocktake"
        " SET status = 'closed'"
        " FROM ranked WHERE stocktake.id = ranked.id AND ranked.rn > 1"
    )
    # Single open stocktake per location/business_date/shift (NULL-safe via coalesce).
    op.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_open_stocktake_shift "
        "ON inv_stocktakes (location_id, business_date, COALESCE(shift_code,'none')) "
        "WHERE status = 'open'"
    )


def downgrade():
    op.execute("DROP INDEX IF EXISTS uq_open_stocktake_shift")
    bind = op.get_bind()
    line_cols = {c["name"] for c in sa.inspect(bind).get_columns("inv_request_lines")}
    if "expiry_date" in line_cols:
        op.drop_column("inv_request_lines", "expiry_date")
    if "lot_no" in line_cols:
        op.drop_column("inv_request_lines", "lot_no")
    if "unit_price" in line_cols:
        op.drop_column("inv_request_lines", "unit_price")
    req_cols = {c["name"] for c in sa.inspect(bind).get_columns("inv_requests")}
    if "received_at" in req_cols:
        op.drop_column("inv_requests", "received_at")
    if "supplier" in req_cols:
        op.drop_column("inv_requests", "supplier")
