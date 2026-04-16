from __future__ import annotations

from typing import Any

import httpx

from nudge_worker.config import Settings


class NtfyClient:
    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.ntfy_base_url.rstrip("/")
        headers: dict[str, str] = {}
        if settings.ntfy_access_token:
            headers["Authorization"] = f"Bearer {settings.ntfy_access_token}"
        self._client = httpx.AsyncClient(timeout=15, headers=headers)

    async def publish(self, topic: str, body: str, title: str | None = None, priority: str | None = None, tags: list[str] | None = None) -> dict[str, Any]:
        headers: dict[str, str] = {}
        if title:
            headers["Title"] = title
        if priority:
            headers["Priority"] = priority
        if tags:
            headers["Tags"] = ",".join(tags)

        response = await self._client.post(f"{self._base_url}/{topic}", content=body.encode("utf-8"), headers=headers)
        response.raise_for_status()
        return {"status": response.status_code, "topic": topic}

    async def close(self) -> None:
        await self._client.aclose()
