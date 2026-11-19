"""Domain model: Drug (generic-level record, NOT a brand product).

Matches migration 003_drug_catalog.sql. A drug represents the active
ingredient-level record; brand products are modelled separately in
brand_products.py.
"""

from sqlalchemy import String, Boolean, Numeric, DateTime, ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class Drug(Base):
    __tablename__ = "drugs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(30), unique=True, nullable=False, index=True)
    name_en: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    name_ar: Mapped[str | None] = mapped_column(String(255), nullable=True)
    generic_name_en: Mapped[str | None] = mapped_column(String(255), nullable=True)
    generic_name_ar: Mapped[str | None] = mapped_column(String(255), nullable=True)
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
    ingredients = relationship("DrugIngredient", back_populates="drug", cascade="all, delete-orphan")
    class_links = relationship("DrugClassLink", back_populates="drug", cascade="all, delete-orphan")
    indications = relationship("DrugIndication", back_populates="drug", cascade="all, delete-orphan")
    contraindications = relationship("DrugContraindication", back_populates="drug", cascade="all, delete-orphan")
    adverse_effects = relationship("DrugAdverseEffect", back_populates="drug", cascade="all, delete-orphan")
    interactions_as_source = relationship(
        "DrugInteraction", back_populates="drug", foreign_keys="DrugInteraction.drug_id",
        cascade="all, delete-orphan"
    )
    dosage_info = relationship("DrugDosageInformation", back_populates="drug", cascade="all, delete-orphan")
    special_populations = relationship("DrugSpecialPopulation", back_populates="drug", cascade="all, delete-orphan")
    images = relationship("DrugImage", back_populates="drug", cascade="all, delete-orphan")
