from __future__ import annotations

from typing import Any

import httpx

from nudge_worker.config import Settings


class AgentServiceClient:
    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.agent_service_base_url.rstrip("/")
        self._client = httpx.AsyncClient(timeout=20)
        self._session_prefix = settings.nudge_session_prefix

    async def coach_message(self, task_id: int, message: str) -> str:
        response = await self._client.post(
            f"{self._base_url}/chat",
            json={
                "session_id": f"{self._session_prefix}:task:{task_id}",
                "message": message,
            },
        )
        response.raise_for_status()
        payload: dict[str, Any] = response.json()
        return str(payload.get("response") or "")

    async def send_task_prompt(
        self,
        *,
        task_id: int,
        task_title: str,
        message_type: str,
        body: str | None = None,
        duration_minutes: int | None = None,
    ) -> dict[str, Any]:
        response = await self._client.post(
            f"{self._base_url}/internal/telegram/send",
            json={
                "task_id": task_id,
                "task_title": task_title,
                "message_type": message_type,
                "text": body or "",
                "duration_minutes": duration_minutes,
            },
        )
        response.raise_for_status()
        payload: dict[str, Any] = response.json()
        return payload

    async def close(self) -> None:
        await self._client.aclose()
