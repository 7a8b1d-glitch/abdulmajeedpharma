"""Domain model: ContentReview.

Matches migration 005_scientific_evidence_and_reviews.sql.
Review workflow records for scientific evidence content.
"""

from sqlalchemy import String, DateTime, Text, ForeignKey, CheckConstraint, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class ContentReview(Base):
    __tablename__ = "content_reviews"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_evidence_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("drug_evidence.id"), nullable=False
    )
    reviewer_id: Mapped[str] = mapped_column(String(36), nullable=False)
    review_status: Mapped[str] = mapped_column(String(30), default="draft", nullable=False)
    review_date: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    review_notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    content_version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    approved_by: Mapped[str | None] = mapped_column(String(36), nullable=True)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            review_status.in_([
                'draft', 'under_review', 'verified', 'needs_update',
                'rejected', 'unpublished'
            ]),
            name="chk_content_review_status",
        ),
    )
