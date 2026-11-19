"""Domain model: MessageReadReceipt.

Matches migration 007_messaging_and_notifications.sql.
"""

from sqlalchemy import String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class MessageReadReceipt(Base):
    __tablename__ = "message_read_receipts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    message_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("messages.id"), nullable=False
    )
    user_id: Mapped[str] = mapped_column(String(36), nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    read_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        UniqueConstraint("message_id", "user_id", name="uq_message_read_receipt"),
    )

    # Relationships
    message = relationship("Message", back_populates="read_receipts")
