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

    ntfy_base_url: str = "https://ntfy.example.com"
    ntfy_access_token: Optional[str] = None
    ntfy_focus_topic: str = "focus"
    ntfy_reminders_topic: str = "reminders"
    ntfy_escalation_topic: str = "escalation"

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


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
