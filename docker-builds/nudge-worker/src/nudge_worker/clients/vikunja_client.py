from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import httpx

from nudge_worker.config import Settings
from nudge_worker.models import TaskSnapshot


def _parse_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None


class VikunjaClient:
    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.vikunja_base_url.rstrip("/") + "/api/v1"
        self._project_id = settings.vikunja_project_id
        self._client = httpx.AsyncClient(
            timeout=settings.vikunja_timeout_seconds,
            headers={
                "Authorization": f"Bearer {settings.vikunja_api_token}",
                "Content-Type": "application/json",
            },
        )

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        response = await self._client.request(method, f"{self._base_url}{path}", **kwargs)
        response.raise_for_status()
        if not response.content:
            return {}
        return response.json()

    async def list_open_tasks(self, limit: int = 50) -> list[TaskSnapshot]:
        tasks = await self._request("GET", "/tasks/all")
        if not isinstance(tasks, list):
            return []

        snapshots: list[TaskSnapshot] = []
        for task in tasks:
            if not isinstance(task, dict) or task.get("done", False):
                continue
            snapshots.append(
                TaskSnapshot(
                    task_id=int(task.get("id", 0)),
                    title=str(task.get("title", "Untitled task")),
                    due_date=_parse_datetime(task.get("due_date")),
                    start_date=_parse_datetime(task.get("start_date")),
                    updated_at=_parse_datetime(task.get("updated")),
                    done=bool(task.get("done", False)),
                    percent_done=float(task.get("percent_done") or 0.0),
                    priority=int(task.get("priority") or 0),
                    raw=task,
                )
            )
        far_future = datetime.max.replace(tzinfo=timezone.utc)
        snapshots.sort(key=lambda item: (item.due_date or far_future, -item.priority))
        return snapshots[: max(1, limit)]

    async def get_task(self, task_id: int) -> dict[str, Any]:
        return await self._request("GET", f"/tasks/{task_id}")

    async def update_task(self, task_id: int, **changes: Any) -> dict[str, Any]:
        current = await self.get_task(task_id)
        payload = dict(current)
        payload.update({key: value for key, value in changes.items() if value is not None})
        return await self._request("POST", f"/tasks/{task_id}", json=payload)

    async def close(self) -> None:
        await self._client.aclose()
