"""Domain model: Message.

Matches migration 007_messaging_and_notifications.sql.
"""

from sqlalchemy import String, DateTime, Text, ForeignKey, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    conversation_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("conversations.id"), nullable=False
    )
    sender_id: Mapped[str] = mapped_column(String(36), nullable=False)
    body_en: Mapped[str] = mapped_column(Text, nullable=False)
    body_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    message_type: Mapped[str] = mapped_column(String(30), default="text", nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            message_type.in_(['text', 'system', 'attachment']),
            name="chk_message_type",
        ),
    )

    # Relationships
    conversation = relationship("Conversation", back_populates="messages")
    attachments = relationship("MessageAttachment", back_populates="message", cascade="all, delete-orphan")
    read_receipts = relationship("MessageReadReceipt", back_populates="message", cascade="all, delete-orphan")
