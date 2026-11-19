"""Domain model: DrugImage.

Matches migration 003_drug_catalog.sql.
"""

from sqlalchemy import String, DateTime, ForeignKey, Text, Boolean
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class DrugImage(Base):
    __tablename__ = "drug_images"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_id: Mapped[str] = mapped_column(String(36), ForeignKey("drugs.id"), nullable=False)
    storage_path: Mapped[str] = mapped_column(Text, nullable=False)
    alt_text_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    alt_text_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    # Relationships
    drug = relationship("Drug", back_populates="images")
