"""Domain model: ProductRegistrationRecord.

Matches migration 004_companies_and_market.sql.
Registration records per country/market. Unknown status stays unknown.
"""

from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class ProductRegistrationRecord(Base):
    __tablename__ = "product_registration_records"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    product_market_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("product_markets.id"), nullable=False
    )
    registration_number: Mapped[str | None] = mapped_column(String(100), nullable=True)
    registration_status: Mapped[str] = mapped_column(
        String(30), default="unknown", nullable=False
    )
    registration_authority: Mapped[str | None] = mapped_column(String(100), nullable=True)
    registration_verification_date: Mapped[DateTime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    availability_status: Mapped[str] = mapped_column(
        String(30), default="unknown", nullable=False
    )
    market_notes_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    market_notes_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    source_reference: Mapped[str | None] = mapped_column(Text, nullable=True)
    last_verified_date: Mapped[DateTime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            registration_status.in_([
                'unknown', 'registered', 'pending', 'rejected',
                'expired', 'withdrawn', 'suspended'
            ]),
            name="chk_registration_status",
        ),
        CheckConstraint(
            availability_status.in_([
                'unknown', 'available', 'out_of_stock', 'discontinued'
            ]),
            name="chk_availability_status",
        ),
    )
