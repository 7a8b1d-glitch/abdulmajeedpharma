"""Domain model: AuditLog.

Matches migration 008_imports_and_audit.sql.

Security: audit_logs must NEVER store passwords, tokens, or secrets.
Application roles cannot INSERT/UPDATE/DELETE directly; the backend
service writes entries using the service role (RLS bypass).
"""

from sqlalchemy import String, DateTime, Text, ForeignKey, CheckConstraint
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.dialects.postgresql import JSONB, INET
from sqlalchemy.sql import func

from app.models.base import Base


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    actor_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    actor_role: Mapped[str | None] = mapped_column(String(30), nullable=True)
    action: Mapped[str] = mapped_column(String(50), nullable=False)
    entity_type: Mapped[str] = mapped_column(String(50), nullable=False)
    entity_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    timestamp: Mapped[DateTime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    change_metadata: Mapped[dict] = mapped_column(JSONB, default={}, nullable=False)
    ip_address: Mapped[str | None] = mapped_column(INET, nullable=True)
    user_agent: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "change_metadata ? 'password' IS NOT TRUE AND "
            "change_metadata ? 'access_token' IS NOT TRUE AND "
            "change_metadata ? 'service_key' IS NOT TRUE",
            name="chk_audit_no_secrets",
        ),
    )
