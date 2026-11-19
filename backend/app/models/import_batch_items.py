"""Domain model: ImportBatchItem.

Matches migration 008_imports_and_audit.sql.
"""

from sqlalchemy import String, DateTime, Integer, ForeignKey, Text, UniqueConstraint, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.sql import func

from app.models.base import Base


class ImportBatchItem(Base):
    __tablename__ = "import_batch_items"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    import_batch_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("import_batches.id"), nullable=False
    )
    row_number: Mapped[int] = mapped_column(Integer, nullable=False)
    source_payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="pending", nullable=False)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("import_batch_id", "row_number", name="uq_import_batch_item_row"),
        CheckConstraint(
            status.in_(['pending', 'imported', 'failed', 'duplicate']),
            name="chk_import_item_status",
        ),
    )

    # Relationships
    import_batch = relationship("ImportBatch", back_populates="items")
