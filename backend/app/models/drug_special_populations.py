"""Domain model: DrugSpecialPopulation.

Matches migration 003_drug_catalog.sql.
"""

from sqlalchemy import String, DateTime, ForeignKey, Text, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class DrugSpecialPopulation(Base):
    __tablename__ = "drug_special_populations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_id: Mapped[str] = mapped_column(String(36), ForeignKey("drugs.id"), nullable=False)
    population: Mapped[str] = mapped_column(String(100), nullable=False)
    guidance_en: Mapped[str] = mapped_column(Text, nullable=False)
    guidance_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    risk_level: Mapped[str | None] = mapped_column(String(30), nullable=True)
    source_ref: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            risk_level.in_(['safe', 'caution', 'contraindicated', 'unknown']),
            name="chk_drug_special_population_risk_level",
        ),
    )

    # Relationships
    drug = relationship("Drug", back_populates="special_populations")
