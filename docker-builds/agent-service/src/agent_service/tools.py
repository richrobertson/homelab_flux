from __future__ import annotations

from typing import Any

from agent_service.clients.vikunja_client import VikunjaClient

TOOL_SCHEMAS: list[dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "list_tasks",
            "description": "List open tasks, optionally only overdue tasks.",
            "parameters": {
                "type": "object",
                "properties": {
                    "overdue_only": {"type": "boolean", "default": False},
                    "limit": {"type": "integer", "minimum": 1, "maximum": 100, "default": 25},
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "create_task",
            "description": "Create a task in Vikunja.",
            "parameters": {
                "type": "object",
                "properties": {
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "due_date": {
                        "type": "string",
                        "description": "ISO-8601 timestamp, for example 2026-04-16T10:00:00Z",
                    },
                    "project_id": {"type": "integer"},
                },
                "required": ["title"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "update_task",
            "description": "Update task title, description, or due date.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {"type": "integer"},
                    "title": {"type": "string"},
                    "description": {"type": "string"},
                    "due_date": {
                        "type": "string",
                        "description": "ISO-8601 timestamp",
                    },
                },
                "required": ["task_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "complete_task",
            "description": "Mark a task done.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {"type": "integer"},
                },
                "required": ["task_id"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "suggest_next_task",
            "description": "Suggest the best next task from open tasks.",
            "parameters": {
                "type": "object",
                "properties": {
                    "limit": {"type": "integer", "minimum": 1, "maximum": 50, "default": 20}
                },
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "break_down_task",
            "description": "Break a task into smaller concrete steps.",
            "parameters": {
                "type": "object",
                "properties": {
                    "task_id": {"type": "integer"},
                    "title": {"type": "string"},
                },
            },
        },
    },
]


class ToolExecutor:
    def __init__(self, vikunja: VikunjaClient) -> None:
        self._vikunja = vikunja

    async def execute(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        handlers = {
            "list_tasks": self._list_tasks,
            "create_task": self._create_task,
            "update_task": self._update_task,
            "complete_task": self._complete_task,
            "suggest_next_task": self._suggest_next_task,
            "break_down_task": self._break_down_task,
        }
        if name not in handlers:
            return {"ok": False, "error": f"Unknown tool: {name}"}

        try:
            return await handlers[name](arguments)
        except Exception as exc:  # noqa: BLE001
            return {"ok": False, "error": str(exc)}

    async def _list_tasks(self, args: dict[str, Any]) -> dict[str, Any]:
        tasks = await self._vikunja.list_tasks(
            overdue_only=bool(args.get("overdue_only", False)),
            limit=int(args.get("limit", 25)),
        )
        return {"ok": True, "count": len(tasks), "tasks": tasks}

    async def _create_task(self, args: dict[str, Any]) -> dict[str, Any]:
        task = await self._vikunja.create_task(
            title=str(args["title"]),
            description=args.get("description"),
            due_date=args.get("due_date"),
            project_id=args.get("project_id"),
        )
        return {"ok": True, "task": task}

    async def _update_task(self, args: dict[str, Any]) -> dict[str, Any]:
        task = await self._vikunja.update_task(
            task_id=int(args["task_id"]),
            title=args.get("title"),
            description=args.get("description"),
            due_date=args.get("due_date"),
        )
        return {"ok": True, "task": task}

    async def _complete_task(self, args: dict[str, Any]) -> dict[str, Any]:
        task = await self._vikunja.complete_task(task_id=int(args["task_id"]))
        return {"ok": True, "task": task}

    async def _suggest_next_task(self, args: dict[str, Any]) -> dict[str, Any]:
        tasks = await self._vikunja.list_tasks(limit=int(args.get("limit", 20)))
        if not tasks:
            return {"ok": True, "suggestion": None, "reason": "No open tasks found."}

        tasks.sort(key=lambda t: (t.get("due_date") or "9999", -(t.get("priority") or 0)))
        top = tasks[0]
        return {
            "ok": True,
            "suggestion": {
                "id": top.get("id"),
                "title": top.get("title"),
                "due_date": top.get("due_date"),
                "priority": top.get("priority"),
                "task_url": top.get("task_url"),
            },
        }

    async def _break_down_task(self, args: dict[str, Any]) -> dict[str, Any]:
        title = args.get("title")
        task_id = args.get("task_id")
        if task_id is not None:
            task = await self._vikunja.get_task(int(task_id))
            title = task.get("title") or title

        if not title:
            return {"ok": False, "error": "Provide task_id or title."}

        steps = [
            f"Define the exact outcome for '{title}'.",
            "Spend 10 minutes gathering context and constraints.",
            "Create a first small deliverable you can finish in under 30 minutes.",
            "Review progress and identify the next concrete step.",
        ]
        return {"ok": True, "title": title, "steps": steps}
