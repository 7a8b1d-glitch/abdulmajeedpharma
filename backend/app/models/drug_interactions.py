"""Domain model: DrugInteraction — pairwise drug interactions.

Matches migration 003_drug_catalog.sql.
"""

from sqlalchemy import String, DateTime, ForeignKey, Text, CheckConstraint, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class DrugInteraction(Base):
    __tablename__ = "drug_interactions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_id: Mapped[str] = mapped_column(String(36), ForeignKey("drugs.id"), nullable=False)
    interacting_drug_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("drugs.id"), nullable=False
    )
    interaction_en: Mapped[str] = mapped_column(Text, nullable=False)
    interaction_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    severity: Mapped[str | None] = mapped_column(String(30), nullable=True)
    source_ref: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            severity.in_(['minor', 'moderate', 'major', 'contraindicated']),
            name="chk_drug_interaction_severity",
        ),
        UniqueConstraint(
            "drug_id", "interacting_drug_id",
            name="uq_drug_interaction_pair_directed",
        ),
        CheckConstraint(
            "drug_id <> interacting_drug_id",
            name="chk_drug_not_self_interaction",
        ),
    )

    # Relationships
    drug = relationship("Drug", back_populates="interactions_as_source", foreign_keys=[drug_id])
