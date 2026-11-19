"""Domain model: UserProfile.

Matches migration 006_users_and_permissions.sql.
Linked to Supabase auth.users via user_id -> auth.users(id).
"""

from sqlalchemy import String, Boolean, DateTime, Text, ForeignKey, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql import func

from app.models.base import Base


class UserProfile(Base):
    __tablename__ = "user_profiles"

    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("auth.users.id"), primary_key=True
    )
    full_name: Mapped[str | None] = mapped_column(Text, nullable=True)
    email: Mapped[str] = mapped_column(String(255), nullable=False)
    role: Mapped[str] = mapped_column(
        String(30), default="user", nullable=False
    )
    phone: Mapped[str | None] = mapped_column(String(30), nullable=True)
    country_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("countries.id"), nullable=True
    )
    language: Mapped[str] = mapped_column(String(10), default="ar", nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        CheckConstraint(
            role.in_(['user', 'editor', 'scientific_reviewer', 'administrator']),
            name="chk_user_profile_role",
        ),
    )
