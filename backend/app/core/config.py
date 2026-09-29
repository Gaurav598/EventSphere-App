from datetime import timedelta
from functools import cached_property
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    PROJECT_NAME: str = "EventSphere API"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: Literal["development", "test", "production"] = "development"

    MONGO_URI: str = "mongodb://localhost:27017"
    MONGO_DB_NAME: str = "eventsphere"
    MONGO_CONNECT_TIMEOUT_SECONDS: int = Field(default=10, ge=1, le=60)

    REDIS_URL: str = "redis://localhost:6379/0"
    REDIS_SOCKET_TIMEOUT_SECONDS: int = Field(default=2, ge=1, le=30)
    EVENT_CACHE_TTL_SECONDS: int = Field(default=300, ge=1, le=3600)
    CHECKIN_GRACE_HOURS: int = Field(default=12, ge=0, le=168)
    ORGANIZER_SIGNUP_CODE: str | None = Field(default=None, min_length=12)

    JWT_SECRET: str = Field(
        default="development-only-secret-change-before-production-0123456789",
        min_length=32,
    )
    JWT_EXPIRE_MINUTES: int = Field(default=1440, ge=5, le=10080)
    JWT_ALGORITHM: Literal["HS256"] = "HS256"
    JWT_ISSUER: str = "eventsphere"
    JWT_AUDIENCE: str = "eventsphere-clients"

    CORS_ORIGINS: str = (
        "http://localhost,http://127.0.0.1,"
        "http://localhost:3000,http://127.0.0.1:3000"
    )
    ALLOWED_HOSTS: str = "*"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=True,
    )

    @cached_property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",") if origin.strip()]

    @cached_property
    def allowed_hosts(self) -> list[str]:
        return [host.strip() for host in self.ALLOWED_HOSTS.split(",") if host.strip()]

    @cached_property
    def ticket_checkin_grace(self) -> timedelta:
        return timedelta(hours=self.CHECKIN_GRACE_HOURS)

    @model_validator(mode="after")
    def validate_production_secrets(self) -> "Settings":
        if self.ENVIRONMENT == "production" and "development-only" in self.JWT_SECRET:
            raise ValueError("JWT_SECRET must be replaced in production")
        return self


settings = Settings()
