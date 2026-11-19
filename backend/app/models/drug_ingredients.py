"""Domain model: DrugIngredient — many-to-many link Drug <-> ActiveIngredient.

Matches migration 003_drug_catalog.sql.
"""

from sqlalchemy import String, Boolean, Numeric, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class DrugIngredient(Base):
    __tablename__ = "drug_ingredients"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_id: Mapped[str] = mapped_column(String(36), ForeignKey("drugs.id"), nullable=False)
    active_ingredient_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("active_ingredients.id"), nullable=False
    )
    strength_value: Mapped[float | None] = mapped_column(Numeric(10, 4), nullable=True)
    strength_unit: Mapped[str | None] = mapped_column(String(30), nullable=True)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("drug_id", "active_ingredient_id", name="uq_drug_ingredient_pair"),
    )

    # Relationships
    drug = relationship("Drug", back_populates="ingredients")
    active_ingredient = relationship("ActiveIngredient", back_populates="drug_links")
