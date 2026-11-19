"""Application configuration loaded from environment variables."""

from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    # Application
    app_name: str = "Abdulmajeedpharma"
    app_short_name: str = "APH"
    app_env: str = "development"
    debug: bool = True

    # Database URL (PostgreSQL cloud)
    database_url: str = "postgresql+asyncpg://aph_user:CHANGE_ME@localhost:5432/aph_db"

    # Supabase (Auth + Storage)
    supabase_url: str = "https://placeholder.supabase.co"
    supabase_public_key: str = "PLACEHOLDER_PUBLIC_ANON_KEY"
    supabase_service_key: str = "PLACEHOLDER_SERVICE_ROLE_KEY"

    # Redis
    redis_url: str = "redis://localhost:6379/0"

    # AI provider
    ai_provider: str = "google_vertex_ai"
    ai_api_key: str = "PLACEHOLDER_AI_API_KEY"

    # Google Cloud
    google_cloud_project: str = "aph-project-xxxx"

    # Search service
    search_service_url: str = "http://localhost:9200"
    search_api_key: str = "PLACEHOLDER_SEARCH_KEY"

    # JWT
    jwt_secret: str = "CHANGE_ME_JWT_SECRET_MIN_32_CHARS"
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30

    # CORS
    cors_origins: List[str] = ["http://localhost:3000", "http://localhost:8000"]

    # Support contact
    support_email: str = "support@abdulmajeedpharma.example"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8", "extra": "ignore"}


settings = Settings()
