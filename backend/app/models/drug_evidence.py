"""Domain model: DrugEvidence.

Matches migration 005_scientific_evidence_and_reviews.sql.
Evidence claims linked to a drug or brand product and a scientific source.
"""

from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class DrugEvidence(Base):
    __tablename__ = "drug_evidence"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("drugs.id"), nullable=True
    )
    brand_product_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("brand_products.id"), nullable=True
    )
    scientific_source_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("scientific_sources.id"), nullable=False
    )
    claim_category: Mapped[str] = mapped_column(String(40), nullable=False)
    claim_text_en: Mapped[str] = mapped_column(Text, nullable=False)
    claim_text_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )
    created_by: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("user_profiles.user_id"), nullable=True
    )

    __table_args__ = (
        CheckConstraint(
            claim_category.in_([
                'mechanism_of_action', 'indications', 'contraindications',
                'adverse_effects', 'interactions', 'dosage', 'pharmacokinetics',
                'pregnancy_and_lactation', 'renal_and_hepatic', 'toxicity',
                'other'
            ]),
            name="chk_drug_evidence_claim_category",
        ),
        CheckConstraint(
            "drug_id IS NOT NULL OR brand_product_id IS NOT NULL",
            name="chk_drug_evidence_target",
        ),
        CheckConstraint(
            "NOT (drug_id IS NOT NULL AND brand_product_id IS NOT NULL)",
            name="chk_drug_evidence_single_target",
        ),
    )
