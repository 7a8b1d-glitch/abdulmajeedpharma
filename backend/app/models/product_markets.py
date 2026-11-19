"""Domain model: ProductMarket.

Matches migration 004_companies_and_market.sql. Country-level market
availability for a brand product.
"""

from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class ProductMarket(Base):
    __tablename__ = "product_markets"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    brand_product_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("brand_products.id"), nullable=False
    )
    country_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("countries.id"), nullable=False
    )
    distribution_allowed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    notes_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    notes_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
