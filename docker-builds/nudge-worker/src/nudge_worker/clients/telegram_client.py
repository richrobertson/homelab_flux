from __future__ import annotations

from typing import Any

import httpx

TELEGRAM_TEXT_LIMIT = 4000


class TelegramClient:
    def __init__(self, bot_token: str | None, timeout_seconds: float = 15.0) -> None:
        self._bot_token = (bot_token or "").strip()
        self._client = httpx.AsyncClient(timeout=timeout_seconds)

    @property
    def enabled(self) -> bool:
        return bool(self._bot_token)

    async def send_message(self, chat_id: int, text: str) -> dict[str, Any]:
        if not self.enabled:
            return {"ok": False, "reason": "telegram_disabled"}
        safe_text = (text or "").strip()
        if len(safe_text) > TELEGRAM_TEXT_LIMIT:
            safe_text = safe_text[: TELEGRAM_TEXT_LIMIT - 1] + "..."
        response = await self._client.post(
            f"https://api.telegram.org/bot{self._bot_token}/sendMessage",
            json={"chat_id": chat_id, "text": safe_text},
        )
        response.raise_for_status()
        payload: dict[str, Any] = response.json()
        return payload

    async def close(self) -> None:
        await self._client.aclose()
