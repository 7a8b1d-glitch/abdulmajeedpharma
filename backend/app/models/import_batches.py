"""Domain model: ImportBatch.

Matches migration 008_imports_and_audit.sql.
"""

from sqlalchemy import String, DateTime, Integer, ForeignKey, Text, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.sql import func

from app.models.base import Base


class ImportBatch(Base):
    __tablename__ = "import_batches"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    original_filename: Mapped[str] = mapped_column(Text, nullable=False)
    import_format: Mapped[str] = mapped_column(String(20), nullable=False)
    uploader_id: Mapped[str] = mapped_column(String(36), nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="pending", nullable=False)
    total_records: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    successful_records: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    failed_records: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    duplicate_records: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    started_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    completed_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    error_summary: Mapped[str | None] = mapped_column(Text, nullable=True)
    resumability_metadata: Mapped[dict] = mapped_column(JSONB, default={}, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            import_format.in_(['csv', 'xlsx', 'json', 'zip_with_images']),
            name="chk_import_format",
        ),
        CheckConstraint(
            status.in_([
                'pending', 'running', 'completed', 'failed',
                'partially_completed', 'paused'
            ]),
            name="chk_import_batch_status",
        ),
    )

    # Relationships
    items = relationship("ImportBatchItem", back_populates="import_batch", cascade="all, delete-orphan")
    errors = relationship("ImportError", back_populates="import_batch", cascade="all, delete-orphan")
