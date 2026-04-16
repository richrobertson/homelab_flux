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

    async def close(self) -> None:
        await self._client.aclose()
