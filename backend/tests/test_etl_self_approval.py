"""R11 — ETL `balance_adjustment_admin` không được tự duyệt phiếu của chính mình.

- Runner tự post (runner == actor) => KHÔNG được tạo phiếu `approved` bởi chính
  maker. Chỉ chấp nhận khi actor có capability review (`etl:review`) **và** ghi
  nhận rõ override (audit event + trạng thái riêng: phiếu `draft` chờ duyệt).
- Runner ≠ actor => maker ≠ checker, phiếu `approved` như cũ.
"""
from __future__ import annotations

import uuid
from decimal import Decimal

import pytest
from sqlalchemy import delete, select

from app.api.errors import AppError
from app.database import AsyncSessionLocal
from app.models.activity import AuditEvent
from app.models.etl import EtlConnection, EtlPipeline, EtlRun, EtlRunRow
from app.models.iam import Role, User, UserRole, UserStatus
from app.models.inventory import (
    Balance,
    InventoryRequest,
    InventoryRequestLine,
    Item,
    Location,
    Movement,
)
from app.services import etl_engine


async def _seed_run(session, runner_id: str, *, sku: str, location_id, target_qty: float):
    conn = EtlConnection(id=uuid.uuid4(), name=f"conn-{uuid.uuid4().hex[:8]}", type="json")
    session.add(conn)
    await session.flush()
    pipeline = EtlPipeline(
        id=uuid.uuid4(),
        name=f"pipe-{uuid.uuid4().hex[:8]}",
        target="balance_adjustment_admin",
        connection_id=conn.id,
        location_id=location_id,
    )
    session.add(pipeline)
    await session.flush()
    run = EtlRun(
        id=uuid.uuid4(),
        pipeline_id=pipeline.id,
        runner_id=runner_id,
        status="staged",
        total_rows=1,
        valid_rows=1,
        source_fingerprint=uuid.uuid4().hex,
    )
    session.add(run)
    await session.flush()
    row = EtlRunRow(
        id=uuid.uuid4(),
        run_id=run.id,
        row_number=1,
        raw_data_json={"sku": sku},
        canonical_data_json={"sku": sku, "target_quantity": target_qty},
        valid=True,
        action_preview={
            "action": "balance_adjustment",
            "sku": sku,
            "current_quantity": 0.0,
            "target_quantity": target_qty,
            "delta_quantity": target_qty,
            "direction": "increase",
            "reason": "Kiểm kê ETL",
        },
    )
    session.add(row)
    await session.commit()
    return pipeline, run, conn.id


async def _cleanup(
    session,
    *,
    request_ids: list[str] = (),
    movement_request_ids: list[str] = (),
    run_ids: list = (),
    pipeline_ids: list = (),
    connection_ids: list = (),
) -> None:
    """Xoá dữ liệu test tạo ra (audit_events là append-only nên không xoá)."""
    for request_id in movement_request_ids:
        await session.execute(
            delete(Movement).where(Movement.request_id == uuid.UUID(request_id))
        )
    for request_id in request_ids:
        await session.execute(
            delete(InventoryRequestLine).where(
                InventoryRequestLine.request_id == uuid.UUID(request_id)
            )
        )
        await session.execute(
            delete(InventoryRequest).where(InventoryRequest.id == uuid.UUID(request_id))
        )
    for run_id in run_ids:
        await session.execute(delete(EtlRunRow).where(EtlRunRow.run_id == run_id))
        await session.execute(delete(EtlRun).where(EtlRun.id == run_id))
    for pipeline_id in pipeline_ids:
        await session.execute(delete(EtlPipeline).where(EtlPipeline.id == pipeline_id))
    for connection_id in connection_ids:
        await session.execute(delete(EtlConnection).where(EtlConnection.id == connection_id))
    await session.commit()


@pytest.mark.asyncio
async def test_runner_cannot_self_approve_balance_adjustment():
    """Runner tự post + có `etl:review` => phiếu DRAFT chờ duyệt, không `approved`."""
    async with AsyncSessionLocal() as session:
        admin = (await session.execute(select(User).where(User.username == "demo_admin"))).scalars().first()
        assert admin is not None
        item = (await session.execute(select(Item).limit(1))).scalars().first()
        location = (await session.execute(select(Location).limit(1))).scalars().first()
        assert item is not None and location is not None

        pipeline, run, connection_id = await _seed_run(
            session, admin.id, sku=item.sku, location_id=location.id, target_qty=25.0
        )

        result = await etl_engine.execute_etl_posting(
            db=session,
            run=run,
            pipeline=pipeline,
            actor=admin,
            single_admin_override=True,
        )

        assert result["status"] == "pending_approval"
        assert result["single_admin_override"] is True
        assert result["movements_count"] == 0

        req = await session.get(InventoryRequest, uuid.UUID(result["request_id"]))
        assert req is not None
        assert req.status == "draft", "phiếu không được tự 'approved' bởi chính maker"
        assert req.approver_id is None
        assert str(req.maker_id) == str(admin.id)

        lines = (
            await session.execute(
                select(InventoryRequestLine).where(InventoryRequestLine.request_id == req.id)
            )
        ).scalars().all()
        assert len(lines) == 1

        movements = (
            await session.execute(select(Movement).where(Movement.request_id == req.id))
        ).scalars().all()
        assert movements == [], "chưa duyệt thì chưa được ghi movement"

        audits = (
            await session.execute(
                select(AuditEvent).where(AuditEvent.subject == f"etl_run:{run.id}")
            )
        ).scalars().all()
        actions = [a.action for a in audits]
        assert "etl.balance_adjustment.override_pending" in actions
        override_audit = next(a for a in audits if a.action == "etl.balance_adjustment.override_pending")
        assert override_audit.metadata_json["single_admin_override"] is True
        assert str(override_audit.metadata_json["maker_id"]) == str(admin.id)
        assert str(override_audit.metadata_json["actor_id"]) == str(admin.id)
        assert override_audit.metadata_json["request_status"] == "draft"

        await session.commit()
        await _cleanup(
            session,
            request_ids=[str(req.id)],
            run_ids=[run.id],
            pipeline_ids=[pipeline.id],
            connection_ids=[connection_id],
        )


@pytest.mark.asyncio
async def test_self_approval_without_review_capability_is_forbidden():
    """Runner tự post mà KHÔNG có `etl:review` => 403, không tạo phiếu nào."""
    async with AsyncSessionLocal() as session:
        staff_role = (await session.execute(select(Role).where(Role.code == "staff"))).scalars().first()
        assert staff_role is not None
        staff_id = uuid.uuid4()
        session.add(
            User(
                id=staff_id,
                username=f"etl_staff_{uuid.uuid4().hex[:8]}",
                password_hash="x",
                display_name_demo="ETL staff",
                status=UserStatus.active,
            )
        )
        session.add(UserRole(user_id=staff_id, role_code="staff"))
        await session.commit()

        actor = await session.get(User, staff_id)
        item = (await session.execute(select(Item).limit(1))).scalars().first()
        location = (await session.execute(select(Location).limit(1))).scalars().first()
        pipeline, run, connection_id = await _seed_run(
            session, actor.id, sku=item.sku, location_id=location.id, target_qty=25.0
        )
        run_id = run.id
        pipeline_id = pipeline.id

        with pytest.raises(AppError) as error:
            await etl_engine.execute_etl_posting(
                db=session,
                run=run,
                pipeline=pipeline,
                actor=actor,
                single_admin_override=True,
            )
        assert error.value.http_status == 403
        assert error.value.code == "MAKER_CHECKER_CONFLICT"

        requests = (
            await session.execute(select(InventoryRequest).where(InventoryRequest.maker_id == actor.id))
        ).scalars().all()
        assert requests == []
        await session.rollback()
        await _cleanup(
            session,
            run_ids=[run_id],
            pipeline_ids=[pipeline_id],
            connection_ids=[connection_id],
        )
        await session.execute(delete(UserRole).where(UserRole.user_id == staff_id))
        await session.execute(delete(User).where(User.id == staff_id))
        await session.commit()


@pytest.mark.asyncio
async def test_maker_checker_path_still_approves_when_actor_differs_from_runner():
    """Runner ≠ actor => maker ≠ checker, phiếu `approved` + movement + tồn cập nhật."""
    async with AsyncSessionLocal() as session:
        admin = (await session.execute(select(User).where(User.username == "demo_admin"))).scalars().first()
        approver = (await session.execute(select(User).where(User.username == "demo_approver2"))).scalars().first()
        assert admin is not None and approver is not None
        item = (await session.execute(select(Item).limit(1))).scalars().first()
        location = (await session.execute(select(Location).limit(1))).scalars().first()

        bal_before = (
            await session.execute(
                select(Balance).where(
                    Balance.location_id == location.id, Balance.item_id == item.id
                )
            )
        ).scalars().first()
        qty_before = float(bal_before.quantity) if bal_before else 0.0

        pipeline, run, connection_id = await _seed_run(
            session, admin.id, sku=item.sku, location_id=location.id, target_qty=7.0
        )
        run_id = run.id
        pipeline_id = pipeline.id

        result = await etl_engine.execute_etl_posting(
            db=session,
            run=run,
            pipeline=pipeline,
            actor=approver,
            single_admin_override=False,
        )

        assert result["status"] == "posted"
        req = await session.get(InventoryRequest, uuid.UUID(result["request_id"]))
        assert req.status == "approved"
        assert str(req.maker_id) == str(admin.id)
        assert str(req.approver_id) == str(approver.id)

        movements = (
            await session.execute(select(Movement).where(Movement.request_id == req.id))
        ).scalars().all()
        assert len(movements) == 1

        bal = (
            await session.execute(
                select(Balance).where(
                    Balance.location_id == location.id, Balance.item_id == item.id
                )
            )
        ).scalars().first()
        assert bal is not None
        assert float(bal.quantity) == qty_before + 7.0
        await session.commit()
        await _cleanup(
            session,
            request_ids=[str(req.id)],
            movement_request_ids=[str(req.id)],
            run_ids=[run_id],
            pipeline_ids=[pipeline_id],
            connection_ids=[connection_id],
        )
        # Trả lại tồn ban đầu (DB test dùng chung).
        bal_after = (
            await session.execute(
                select(Balance).where(
                    Balance.location_id == location.id, Balance.item_id == item.id
                )
            )
        ).scalars().first()
        if bal_after is not None:
            bal_after.quantity = Decimal(str(qty_before))
            bal_after.version = bal_after.version
            await session.commit()
