"""Domain model: ProductPresentation.

Matches migration 004_companies_and_market.sql.
Captures strength, form, route, package, barcode for a brand product.
"""

from sqlalchemy import String, Boolean, DateTime, Numeric, Text, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class ProductPresentation(Base):
    __tablename__ = "product_presentations"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    brand_product_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("brand_products.id"), nullable=False
    )
    presentation_code: Mapped[str] = mapped_column(String(30), unique=True, nullable=False, index=True)
    strength_value: Mapped[float | None] = mapped_column(Numeric(10, 4), nullable=True)
    strength_unit: Mapped[str | None] = mapped_column(String(30), nullable=True)
    dosage_form_en: Mapped[str | None] = mapped_column(String(50), nullable=True)
    dosage_form_ar: Mapped[str | None] = mapped_column(String(50), nullable=True)
    route_en: Mapped[str | None] = mapped_column(String(50), nullable=True)
    route_ar: Mapped[str | None] = mapped_column(String(50), nullable=True)
    package_size: Mapped[float | None] = mapped_column(Numeric(10, 4), nullable=True)
    package_unit_en: Mapped[str | None] = mapped_column(String(30), nullable=True)
    package_unit_ar: Mapped[str | None] = mapped_column(String(30), nullable=True)
    barcode: Mapped[str | None] = mapped_column(String(50), nullable=True)
    country_of_origin_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("countries.id"), nullable=True
    )
    image_reference_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("drug_images.id"), nullable=True
    )
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    # Relationships
    brand_product = relationship("BrandProduct", back_populates="presentations")
