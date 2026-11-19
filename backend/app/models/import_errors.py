"""Domain model: ImportError.

Matches migration 008_imports_and_audit.sql.
"""

from sqlalchemy import String, DateTime, Integer, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class ImportError(Base):
    __tablename__ = "import_errors"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    import_batch_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("import_batches.id"), nullable=False
    )
    import_item_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("import_batch_items.id"), nullable=True
    )
    error_code: Mapped[str] = mapped_column(String(50), nullable=False)
    error_message: Mapped[str] = mapped_column(Text, nullable=False)
    row_number: Mapped[int | None] = mapped_column(Integer, nullable=True)
    field_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    import_batch = relationship("ImportBatch", back_populates="errors")
