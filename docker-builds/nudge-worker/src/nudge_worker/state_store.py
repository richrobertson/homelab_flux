from __future__ import annotations

from datetime import datetime, timedelta, timezone

from nudge_worker.models import NudgeHistory


class InMemoryNudgeStateStore:
    def __init__(self) -> None:
        self._history: dict[int, NudgeHistory] = {}

    async def should_send(self, task_id: int, reason: str, cooldown_minutes: int, now: datetime) -> bool:
        history = self._history.get(task_id)
        if not history or not history.last_sent_at:
            return True
        if history.last_reason != reason:
            return True
        return now - history.last_sent_at >= timedelta(minutes=cooldown_minutes)

    async def record_sent(self, task_id: int, reason: str, now: datetime, cooldown_minutes: int = 0) -> NudgeHistory:
        history = self._history.setdefault(task_id, NudgeHistory())
        history.last_sent_at = now.astimezone(timezone.utc)
        history.last_reason = reason
        history.sent_count += 1
        return history

    async def get(self, task_id: int) -> NudgeHistory:
        return self._history.setdefault(task_id, NudgeHistory())

    async def is_telegram_active(self, chat_id: int, within_seconds: int = 900) -> bool:
        return False
