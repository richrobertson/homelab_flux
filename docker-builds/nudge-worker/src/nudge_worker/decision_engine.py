from __future__ import annotations

from datetime import datetime, timedelta, timezone

from nudge_worker.config import Settings
from nudge_worker.models import NudgeDecision, TaskSnapshot
from nudge_worker.state_store import InMemoryNudgeStateStore


class DecisionEngine:
    def __init__(self, settings: Settings, state_store: InMemoryNudgeStateStore) -> None:
        self._settings = settings
        self._state_store = state_store

    def decide(self, tasks: list[TaskSnapshot], now: datetime | None = None) -> list[NudgeDecision]:
        current_time = now or datetime.now(timezone.utc)
        decisions: list[NudgeDecision] = []

        for task in tasks:
            decision = self._classify_task(task, current_time)
            if not decision:
                continue
            if not self._state_store.should_send(
                task.task_id,
                decision.reason,
                self._settings.nudge_cooldown_minutes,
                current_time,
            ):
                continue
            decisions.append(decision)

        return decisions

    def _classify_task(self, task: TaskSnapshot, now: datetime) -> NudgeDecision | None:
        history = self._state_store.get(task.task_id)

        if task.due_date and task.due_date < now:
            escalate = history.sent_count >= 1
            return NudgeDecision(
                task_id=task.task_id,
                title=task.title,
                reason="overdue",
                topic=self._settings.ntfy_escalation_topic,
                priority="urgent" if history.sent_count >= 2 else "high",
                body=f"'{task.title}' is overdue. Either finish the smallest next step now or deliberately reschedule it.",
                metadata={"due_date": task.due_date.isoformat()},
                escalate_to_chat=escalate,
            )

        if history.sent_count >= self._settings.repeated_nudge_threshold:
            return NudgeDecision(
                task_id=task.task_id,
                title=task.title,
                reason="repeated_drift",
                topic=self._settings.ntfy_escalation_topic,
                priority="high",
                body=f"'{task.title}' keeps slipping. Reply with 'overwhelmed', 'blocked', or 'push this' and we'll change strategy.",
                metadata={"sent_count": history.sent_count},
                escalate_to_chat=True,
            )

        if task.start_date and task.start_date <= now and task.percent_done <= 0:
            return NudgeDecision(
                task_id=task.task_id,
                title=task.title,
                reason="start_window_missed",
                topic=self._settings.ntfy_focus_topic,
                priority="default",
                body=f"Start '{task.title}' with a 5-minute opening move. Don't finish it, just begin.",
                metadata={"start_date": task.start_date.isoformat()},
            )

        if task.due_date and task.due_date <= now + timedelta(minutes=self._settings.due_soon_minutes):
            return NudgeDecision(
                task_id=task.task_id,
                title=task.title,
                reason="due_soon",
                topic=self._settings.ntfy_reminders_topic,
                priority="high",
                body=f"'{task.title}' is due soon. Pick one concrete step you can close before the deadline.",
                metadata={"due_date": task.due_date.isoformat()},
            )

        if task.percent_done > 0 and task.updated_at and task.updated_at < now - timedelta(minutes=self._settings.inactivity_minutes):
            return NudgeDecision(
                task_id=task.task_id,
                title=task.title,
                reason="inactive_in_progress",
                topic=self._settings.ntfy_reminders_topic,
                priority="default",
                body=f"You started '{task.title}' but it has gone quiet. What's the next visible step?",
                metadata={"updated_at": task.updated_at.isoformat(), "percent_done": task.percent_done},
            )

        return None
