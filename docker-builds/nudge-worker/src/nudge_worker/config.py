from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "nudge-worker"
    environment: str = "prod"
    log_level: str = "INFO"

    scan_interval_seconds: int = 300
    due_soon_minutes: int = 15
    inactivity_minutes: int = 90
    nudge_cooldown_minutes: int = 60
    repeated_nudge_threshold: int = 3
    max_tasks_per_scan: int = 50

    openai_api_key: str = ""
    openai_model: str = "gpt-4.1-mini"
    openai_base_url: str = "https://api.openai.com/v1"
    openai_timeout_seconds: float = 30.0

    vikunja_base_url: str = "https://tasks.myrobertson.com"
    vikunja_api_token: str = ""
    vikunja_project_id: int = 1
    vikunja_timeout_seconds: float = 20.0

    postgres_dsn: Optional[str] = None
    postgres_host: str = "task-control-plane-cnpg-rw.default.svc.cluster.local"
    postgres_port: int = 5432
    postgres_database: str = "vikunja"
    postgres_user: str = ""
    postgres_password: str = ""

    redis_url: Optional[str] = None
    redis_key_prefix: str = "tcp"

    ntfy_base_url: str = "https://ntfy.example.com"
    ntfy_access_token: Optional[str] = None
    ntfy_focus_topic: str = "focus"
    ntfy_reminders_topic: str = "reminders"
    ntfy_escalation_topic: str = "escalation"

    telegram_bot_token: Optional[str] = None
    telegram_primary_chat_id: Optional[int] = None
    telegram_priority_minutes: int = 90

    metrics_port: int = 9109

    agent_service_base_url: str = "http://agent-service.default.svc.cluster.local:8080"
    nudge_session_prefix: str = "coach"

    @property
    def has_vikunja_credentials(self) -> bool:
        token = self.vikunja_api_token.strip()
        return bool(token and token.lower() != "set-me")

    @property
    def has_openai_credentials(self) -> bool:
        key = self.openai_api_key.strip()
        return bool(key and key.lower() != "set-me")

    @property
    def effective_postgres_dsn(self) -> str | None:
        if self.postgres_dsn:
            return self.postgres_dsn
        if self.postgres_user and self.postgres_password:
            return (
                f"postgresql://{self.postgres_user}:{self.postgres_password}@"
                f"{self.postgres_host}:{self.postgres_port}/{self.postgres_database}"
            )
        return None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
