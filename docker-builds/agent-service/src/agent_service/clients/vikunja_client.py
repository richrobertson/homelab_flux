from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import httpx

from agent_service.config import Settings


class VikunjaClient:
    def __init__(self, settings: Settings) -> None:
        self._web_base_url = settings.vikunja_base_url.rstrip("/")
        self._base_url = self._web_base_url + "/api/v1"
        self._project_id = settings.vikunja_project_id
        self._client = httpx.AsyncClient(
            timeout=settings.vikunja_timeout_seconds,
            headers={
                "Authorization": f"Bearer {settings.vikunja_api_token}",
                "Content-Type": "application/json",
            },
        )

    def _with_task_url(self, task: dict[str, Any]) -> dict[str, Any]:
        task_id = task.get("id")
        if task_id is None:
            return task

        try:
            task_id = int(task_id)
        except (TypeError, ValueError):
            return task

        result = dict(task)
        result["task_url"] = f"{self._web_base_url}/tasks/{task_id}"
        return result

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        response = await self._client.request(method, f"{self._base_url}{path}", **kwargs)
        response.raise_for_status()
        if not response.content:
            return {}
        return response.json()

    async def list_tasks(self, overdue_only: bool = False, limit: int = 25) -> list[dict[str, Any]]:
        # /tasks/all returns 400 on this Vikunja deployment; /tasks is compatible.
        tasks = await self._request("GET", "/tasks")
        if not isinstance(tasks, list):
            return []

        normalized = [task for task in tasks if isinstance(task, dict)]
        normalized = [task for task in normalized if not task.get("done", False)]

        if overdue_only:
            now = datetime.now(timezone.utc)
            filtered: list[dict[str, Any]] = []
            for task in normalized:
                due_raw = task.get("due_date")
                if not due_raw:
                    continue
                try:
                    due = datetime.fromisoformat(str(due_raw).replace("Z", "+00:00"))
                except ValueError:
                    continue
                if due < now:
                    filtered.append(task)
            normalized = filtered

        normalized.sort(key=lambda t: (t.get("due_date") or "9999", -(t.get("priority") or 0)))
        sliced = normalized[: max(1, limit)]
        return [self._with_task_url(task) for task in sliced]

    async def get_task(self, task_id: int) -> dict[str, Any]:
        task = await self._request("GET", f"/tasks/{task_id}")
        if isinstance(task, dict):
            return self._with_task_url(task)
        return {}

    async def create_task(
        self,
        title: str,
        description: str | None = None,
        due_date: str | None = None,
        project_id: int | None = None,
        parent_task_id: int | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {"title": title}
        if description:
            payload["description"] = description
        if due_date:
            payload["due_date"] = due_date

        target_project = project_id or self._project_id
        created = await self._request("PUT", f"/projects/{target_project}/tasks", json=payload)
        if isinstance(created, dict):
            if parent_task_id is not None:
                child_id = created.get("id")
                if child_id is not None:
                    await self.create_task_relation(
                        base_task_id=int(parent_task_id),
                        other_task_id=int(child_id),
                        relation_kind="subtask",
                    )
            return self._with_task_url(created)
        return {}

    async def create_task_relation(
        self,
        base_task_id: int,
        other_task_id: int,
        relation_kind: str,
    ) -> dict[str, Any]:
        payload = {
            "task_id": int(base_task_id),
            "other_task_id": int(other_task_id),
            "relation_kind": relation_kind,
        }
        relation = await self._request("PUT", f"/tasks/{int(base_task_id)}/relations", json=payload)
        if isinstance(relation, dict):
            return relation
        return {}

    async def update_task(
        self,
        task_id: int,
        title: str | None = None,
        description: str | None = None,
        due_date: str | None = None,
        done: bool | None = None,
    ) -> dict[str, Any]:
        current = await self._request("GET", f"/tasks/{task_id}")
        if not isinstance(current, dict):
            current = {}
        payload = dict(current)
        if title is not None:
            payload["title"] = title
        if description is not None:
            payload["description"] = description
        if due_date is not None:
            payload["due_date"] = due_date
        if done is not None:
            payload["done"] = done
        updated = await self._request("POST", f"/tasks/{task_id}", json=payload)
        if isinstance(updated, dict):
            return self._with_task_url(updated)
        return {}

    async def complete_task(self, task_id: int) -> dict[str, Any]:
        return await self.update_task(task_id=task_id, done=True)

    async def close(self) -> None:
        await self._client.aclose()
