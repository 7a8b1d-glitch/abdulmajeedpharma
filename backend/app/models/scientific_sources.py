"""Domain model: ScientificSource.

Matches migration 005_scientific_evidence_and_reviews.sql.
"""

from sqlalchemy import String, Boolean, DateTime, Text, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func

from app.models.base import Base


class ScientificSource(Base):
    __tablename__ = "scientific_sources"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    organization: Mapped[str] = mapped_column(Text, nullable=False)
    source_type: Mapped[str] = mapped_column(String(50), nullable=False)
    url: Mapped[str | None] = mapped_column(Text, nullable=True)
    doi: Mapped[str | None] = mapped_column(String(100), nullable=True)
    external_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    publication_date: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    access_date: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    language: Mapped[str] = mapped_column(String(10), default="en", nullable=False)
    reliability_level: Mapped[str] = mapped_column(
        String(30), default="medium", nullable=False
    )
    citation_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            source_type.in_([
                'journal_article', 'textbook', 'regulatory_document',
                'pharmacopoeia', 'clinical_trial_registry', 'database',
                'organization_website', 'other'
            ]),
            name="chk_scientific_source_type",
        ),
        CheckConstraint(
            reliability_level.in_(['low', 'medium', 'high', 'authoritative']),
            name="chk_scientific_source_reliability",
        ),
    )
