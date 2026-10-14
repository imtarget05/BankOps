"""Script reset & re-seed dữ liệu mẫu sạch và chuyên nghiệp cho hệ thống BankOps."""
import asyncio
import uuid
from datetime import UTC, datetime

from sqlalchemy import delete, select

from app.database import AsyncSessionLocal
from app.models.activity import AuditEvent, OutboxEvent
from app.models.approval import ApprovalDecision
from app.models.cash_sim import (
    CashBalance,
    CashBox,
    CashEntry,
    CashJournal,
    CashRequest,
)
from app.models.etl import (
    EtlConnection,
    EtlMappingVersion,
    EtlPipeline,
    EtlRun,
    EtlRunRow,
)
from app.models.iam import User
from app.models.integration import (
    IntegrationConnection,
    IntegrationRun,
    IntegrationStagingRow,
)
from app.models.inventory import (
    Asset,
    AssetLog,
    Balance,
    InventoryRequest,
    InventoryRequestLine,
    Item,
    Location,
    Movement,
    Stocktake,
    StocktakeLine,
)
from app.models.reconciliation import ReconciliationException, ReconciliationRun
from app.models.stock_level import StockLevel
from app.seed import seed_demo


async def reset_demo_database():
    """Xoá toàn bộ dữ liệu giao dịch rác và nạp lại dữ liệu ngân hàng chuẩn mực."""
    print("--- Bắt đầu dọn sạch dữ liệu hệ thống demo ---")
    async with AsyncSessionLocal() as db:
        # 1. Xoá các bảng giao dịch & quan hệ phụ thuộc trước
        await db.execute(delete(ApprovalDecision))
        await db.execute(delete(Movement))
        await db.execute(delete(InventoryRequestLine))
        await db.execute(delete(InventoryRequest))
        await db.execute(delete(StocktakeLine))
        await db.execute(delete(Stocktake))
        await db.execute(delete(StockLevel))
        await db.execute(delete(AssetLog))
        await db.execute(delete(Asset))
        await db.execute(delete(Balance))

        await db.execute(delete(CashEntry))
        await db.execute(delete(CashJournal))
        await db.execute(delete(CashRequest))
        await db.execute(delete(CashBalance))

        await db.execute(delete(ReconciliationException))
        await db.execute(delete(ReconciliationRun))

        await db.execute(delete(IntegrationStagingRow))
        await db.execute(delete(IntegrationRun))
        await db.execute(delete(IntegrationConnection))

        await db.execute(delete(EtlRunRow))
        await db.execute(delete(EtlRun))
        await db.execute(delete(EtlMappingVersion))
        await db.execute(delete(EtlPipeline))
        await db.execute(delete(EtlConnection))

        await db.execute(delete(AuditEvent))
        await db.execute(delete(OutboxEvent))

        # 2. Xoá catalog cũ để nạp mới
        await db.execute(delete(Item))
        await db.execute(delete(Location))
        await db.execute(delete(CashBox))
        await db.commit()
        print("Đã xoá sạch các bảng dữ liệu cũ.")

        # 3. Cập nhật tên hiển thị của Users
        user_names = {
            "demo_maker": "Nguyễn Hoàng An (GDV)",
            "demo_checker": "Trần Tuấn Bình (KSV)",
            "demo_auditor": "Lê Khánh Chi (KTNB)",
            "demo_admin": "Phạm Minh Trị (Admin)",
            "demo_approver2": "Hoàng Quốc Việt (Trưởng KSV)",
        }
        for uname, dname in user_names.items():
            user = (await db.execute(select(User).where(User.username == uname))).scalars().first()
            if user:
                user.display_name_demo = dname
        await db.commit()
        print("Đã chuẩn hóa tên cán bộ ngân hàng.")

    # 4. Chạy seed_demo để nạp lại từ sample-data sạch
    await seed_demo()

    # 5. Nạp thêm các kết nối mẫu ngân hàng
    async with AsyncSessionLocal() as db:
        existing_conns = (await db.execute(select(IntegrationConnection))).scalars().all()
        if not existing_conns:
            conns = [
                IntegrationConnection(
                    id=uuid.uuid4(),
                    type="core_banking",
                    name="Cổng Tích Hợp Core Banking T24 (ISO 8583)",
                    status="connected",
                    config_json={"endpoint": "https://core.bankops.internal/api/v2/transactions"},
                ),
                IntegrationConnection(
                    id=uuid.uuid4(),
                    type="napas",
                    name="Cổng Chuyển Mạch Tài Chính Quốc Gia NAPAS",
                    status="connected",
                    config_json={"endpoint": "https://napas.gateway.vn/switch/v1/settlement"},
                ),
                IntegrationConnection(
                    id=uuid.uuid4(),
                    type="oracle_gl",
                    name="Sổ Cái Kế Toán Tổng Hợp Oracle GL ERP",
                    status="connected",
                    config_json={"endpoint": "https://gl.erp.internal/soap/v1/ledger"},
                ),
            ]
            db.add_all(conns)
            await db.commit()
            print("Đã nạp 3 kết nối hệ thống ngân hàng chuẩn.")

        # Seed sample ETL Connection & Pipeline
        existing_etl_conn = (await db.execute(select(EtlConnection))).scalars().first()
        if not existing_etl_conn:
            loc = (await db.execute(select(Location))).scalars().first()
            admin_user = (await db.execute(select(User).where(User.username == "demo_admin"))).scalars().first()
            etl_conn = EtlConnection(
                id=uuid.uuid4(),
                type="csv",
                name="Kết nối Tệp CSV/Excel Chi nhánh Bến Thành",
                status="active",
                owner_id=admin_user.id if admin_user else None,
            )
            db.add(etl_conn)
            await db.flush()

            etl_pipe = EtlPipeline(
                id=uuid.uuid4(),
                name="Đồng bộ Tồn kho & Điều chỉnh Quản trị Bến Thành",
                target="balance_adjustment_admin",
                connection_id=etl_conn.id,
                location_id=loc.id if loc else None,
                status="active",
                owner_id=admin_user.id if admin_user else None,
            )
            db.add(etl_pipe)
            await db.flush()

            mv = EtlMappingVersion(
                id=uuid.uuid4(),
                pipeline_id=etl_pipe.id,
                version=1,
                status="published",
                mapping_json=[
                    {"source_field": "sku", "target_field": "sku", "required": True, "transform": "trim_upper"},
                    {"source_field": "target_quantity", "target_field": "target_quantity", "required": False, "transform": "to_float"},
                    {"source_field": "delta_quantity", "target_field": "delta_quantity", "required": False, "transform": "to_float"},
                    {"source_field": "reason", "target_field": "reason", "required": False, "transform": "trim", "default": "Điều chỉnh tồn ETL Admin"},
                ],
                duplicate_policy="reject",
                created_by=admin_user.id if admin_user else None,
                published_at=datetime.now(UTC),
            )
            db.add(mv)
            await db.commit()
            print("Đã nạp ETL Pipeline và Mapping Version mẫu.")

    print("--- Hoàn tất reset và re-seed dữ liệu ngân hàng sạch! ---")


if __name__ == "__main__":
    asyncio.run(reset_demo_database())
