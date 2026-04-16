from __future__ import annotations

from datetime import datetime, timedelta, timezone

from nudge_worker.config import Settings
from nudge_worker.models import NudgeDecision, TaskSnapshot


class DecisionEngine:
    def __init__(self, settings: Settings, state_store: object) -> None:
        self._settings = settings
        self._state_store = state_store

    async def decide(
        self,
        tasks: list[TaskSnapshot],
        now: datetime | None = None,
        learning_snapshot: dict | None = None,
    ) -> list[NudgeDecision]:
        current_time = now or datetime.now(timezone.utc)
        decisions: list[NudgeDecision] = []
        snapshot = learning_snapshot or {}
        high_friction_tasks = set(snapshot.get("high_friction_tasks") or [])

        for task in tasks:
            history = await self._state_store.get(task.task_id)
            decision = self._classify_task(task, current_time, history.sent_count, high_friction_tasks)
            if not decision:
                continue
            if not await self._state_store.should_send(
                task.task_id,
                decision.reason,
                self._settings.nudge_cooldown_minutes,
                current_time,
            ):
                continue
            decisions.append(decision)

        return decisions

    def _classify_task(
        self,
        task: TaskSnapshot,
        now: datetime,
        sent_count: int,
        high_friction_tasks: set[int],
    ) -> NudgeDecision | None:
        if task.due_date and task.due_date < now:
            escalate = sent_count >= 1
            return NudgeDecision(
                task_id=task.task_id,
                title=task.title,
                reason="overdue",
                topic=self._settings.ntfy_escalation_topic,
                priority="urgent" if sent_count >= 2 else "high",
                body=f"'{task.title}' is overdue. Either finish the smallest next step now or deliberately reschedule it.",
                metadata={"due_date": task.due_date.isoformat()},
                escalate_to_chat=escalate,
            )

        if task.task_id in high_friction_tasks or sent_count >= self._settings.repeated_nudge_threshold:
            return NudgeDecision(
                task_id=task.task_id,
                title=task.title,
                reason="repeated_drift",
                topic=self._settings.ntfy_escalation_topic,
                priority="high",
                body=f"'{task.title}' keeps slipping. Reply with START, SNOOZE 15, BLOCKED, or BREAK IT DOWN.",
                metadata={"sent_count": sent_count},
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
