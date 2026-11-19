"""Domain model: DrugClassLink — many-to-many link Drug <-> DrugClass.

Matches migration 003_drug_catalog.sql.
"""

from sqlalchemy import String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class DrugClassLink(Base):
    __tablename__ = "drug_class_links"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    drug_id: Mapped[str] = mapped_column(String(36), ForeignKey("drugs.id"), nullable=False)
    drug_class_id: Mapped[str] = mapped_column(String(36), ForeignKey("drug_classes.id"), nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("drug_id", "drug_class_id", name="uq_drug_class_pair"),
    )

    # Relationships
    drug = relationship("Drug", back_populates="class_links")
