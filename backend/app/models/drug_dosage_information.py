"""Domain model: DrugDosageInformation.

Matches migration 003_drug_catalog.sql.
"""

from sqlalchemy import String, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class DrugDosageInformation(Base):
    __tablename__ = "drug_dosage_information"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_id: Mapped[str] = mapped_column(String(36), ForeignKey("drugs.id"), nullable=False)
    population: Mapped[str | None] = mapped_column(String(100), nullable=True)
    dosage_en: Mapped[str] = mapped_column(Text, nullable=False)
    dosage_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    frequency_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    frequency_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    route_en: Mapped[str | None] = mapped_column(String(50), nullable=True)
    route_ar: Mapped[str | None] = mapped_column(String(50), nullable=True)
    source_ref: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    # Relationships
    drug = relationship("Drug", back_populates="dosage_info")
