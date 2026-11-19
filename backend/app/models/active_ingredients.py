"""Domain model: Active Ingredient.

Matches migration 003_drug_catalog.sql. Generic active ingredients (INN).
A drug may contain multiple active ingredients via drug_ingredients.
"""

from sqlalchemy import String, Boolean, Text, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class ActiveIngredient(Base):
    __tablename__ = "active_ingredients"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(30), unique=True, nullable=False, index=True)
    name_en: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    name_ar: Mapped[str | None] = mapped_column(String(255), nullable=True)
    cas_number: Mapped[str | None] = mapped_column(String(30), nullable=True)
    description_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    description_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    created_by: Mapped[str | None] = mapped_column(String(36), ForeignKey("user_profiles.user_id"), nullable=True)

    # Relationships
    drug_links = relationship("DrugIngredient", back_populates="active_ingredient", cascade="all, delete-orphan")
