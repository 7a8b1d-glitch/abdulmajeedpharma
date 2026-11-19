"""Domain model: PharmacologicalClass.

Matches migration 002_geography_and_classification.sql.
"""

from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class PharmacologicalClass(Base):
    __tablename__ = "pharmacological_classes"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    therapeutic_class_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("therapeutic_classes.id"), nullable=False
    )
    code: Mapped[str] = mapped_column(String(20), unique=True, nullable=False, index=True)
    name_en: Mapped[str] = mapped_column(String(255), nullable=False)
    name_ar: Mapped[str | None] = mapped_column(String(255), nullable=True)
    description_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    description_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
