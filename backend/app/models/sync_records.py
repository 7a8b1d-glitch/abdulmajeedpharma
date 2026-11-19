"""Domain model: SyncRecord.

Matches migration 008_imports_and_audit.sql.
Foundation for future offline synchronization.
"""

from sqlalchemy import String, DateTime, Integer, ForeignKey, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.sql import func

from app.models.base import Base


class SyncRecord(Base):
    __tablename__ = "sync_records"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    client_id: Mapped[str] = mapped_column(String(100), nullable=False)
    table_name: Mapped[str] = mapped_column(String(50), nullable=False)
    record_id: Mapped[str] = mapped_column(String(36), nullable=False)
    record_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    operation: Mapped[str] = mapped_column(String(20), nullable=False)
    server_updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    sync_status: Mapped[str] = mapped_column(String(30), default="pending", nullable=False)
    conflict_metadata: Mapped[dict] = mapped_column(JSONB, default={}, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            operation.in_(['insert', 'update', 'delete']),
            name="chk_sync_operation",
        ),
        CheckConstraint(
            sync_status.in_(['pending', 'synced', 'conflict', 'failed']),
            name="chk_sync_status",
        ),
    )
