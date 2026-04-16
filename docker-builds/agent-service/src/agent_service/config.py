from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "agent-service"
    environment: str = "prod"
    log_level: str = "INFO"

    openai_api_key: str = ""
    openai_model: str = "gpt-4.1-mini"
    openai_base_url: str = "https://api.openai.com/v1"
    openai_timeout_seconds: float = 30.0

    vikunja_base_url: str = "https://tasks.myrobertson.com"
    vikunja_api_token: str = ""
    vikunja_project_id: int = 1
    vikunja_timeout_seconds: float = 20.0

    telegram_bot_token: Optional[str] = None
    telegram_webhook_secret: Optional[str] = None

    session_ttl_seconds: int = 3600
    session_max_messages: int = 20
    tool_max_iterations: int = 4

    agent_system_prompt: Optional[str] = None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
