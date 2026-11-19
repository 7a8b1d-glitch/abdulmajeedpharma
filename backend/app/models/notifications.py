"""Domain model: Notification.

Matches migration 007_messaging_and_notifications.sql.
"""

from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.sql import func

from app.models.base import Base


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), nullable=False)
    type: Mapped[str] = mapped_column(String(40), nullable=False)
    title_en: Mapped[str] = mapped_column(Text, nullable=False)
    title_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    body_en: Mapped[str | None] = mapped_column(Text, nullable=True)
    body_ar: Mapped[str | None] = mapped_column(Text, nullable=True)
    data: Mapped[dict] = mapped_column(JSONB, default={}, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    read_at: Mapped[DateTime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    delivered_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            type.in_([
                'message', 'review_request', 'review_decision',
                'import_complete', 'import_error', 'system',
                'registration_update', 'security'
            ]),
            name="chk_notification_type",
        ),
    )
