"""Domain model: BrandProduct.

Matches migration 004_companies_and_market.sql. A branded/marketed product
(NOT a generic drug). Linked to one manufacturer and one marketing
authorization holder.
"""

from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class BrandProduct(Base):
    __tablename__ = "brand_products"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(30), unique=True, nullable=False, index=True)
    brand_name_en: Mapped[str] = mapped_column(String(255), nullable=False)
    brand_name_ar: Mapped[str | None] = mapped_column(String(255), nullable=True)
    manufacturer_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("manufacturers.id"), nullable=False
    )
    marketing_authorization_holder_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("marketing_authorization_holders.id"), nullable=True
    )
    description_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    description_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    created_by: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_profiles.user_id"), nullable=True
    )

    # Relationships
    presentations = relationship(
        "ProductPresentation", back_populates="brand_product", cascade="all, delete-orphan"
    )
