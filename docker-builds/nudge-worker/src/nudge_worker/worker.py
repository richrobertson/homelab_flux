from __future__ import annotations

import asyncio
import logging
from datetime import date, datetime, timezone

from nudge_worker.clients.agent_service_client import AgentServiceClient
from nudge_worker.clients.ntfy_client import NtfyClient
from nudge_worker.clients.telegram_client import TelegramClient
from nudge_worker.clients.vikunja_client import VikunjaClient
from nudge_worker.coach import CoachingComposer
from nudge_worker.config import Settings
from nudge_worker.decision_engine import DecisionEngine
from nudge_worker.metrics import (
    active_task_sessions,
    nudges_sent_total,
    postgres_event_writes_total,
    redis_state_reads_total,
    redis_state_writes_total,
)
from nudge_worker.models import NudgeDecision

logger = logging.getLogger(__name__)


class NudgeWorker:
    def __init__(
        self,
        settings: Settings,
        vikunja_client: VikunjaClient,
        ntfy_client: NtfyClient,
        state_store: object,
        coach: CoachingComposer,
        postgres_store: object | None = None,
        telegram_client: TelegramClient | None = None,
        agent_service_client: AgentServiceClient | None = None,
    ) -> None:
        self._settings = settings
        self._vikunja = vikunja_client
        self._ntfy = ntfy_client
        self._state = state_store
        self._engine = DecisionEngine(settings, state_store)
        self._coach = coach
        self._agent_service = agent_service_client
        self._postgres = postgres_store
        self._telegram = telegram_client

    async def run_forever(self) -> None:
        while True:
            try:
                await self.run_once()
            except Exception as exc:  # noqa: BLE001
                logger.warning("nudge_scan_failed: %s", exc)
            await asyncio.sleep(self._settings.scan_interval_seconds)

    async def run_once(self) -> list[NudgeDecision]:
        if not self._settings.has_vikunja_credentials:
            logger.warning("vikunja_credentials_missing")
            return []

        now = datetime.now(timezone.utc)
        tasks = await self._vikunja.list_open_tasks(limit=self._settings.max_tasks_per_scan)
        learning = await self._postgres.recent_learning_snapshot() if self._postgres is not None else {}
        decisions = await self._engine.decide(tasks, now=now, learning_snapshot=learning)
        active_task_sessions.set(len(tasks))
        logger.info("nudge_scan_complete", extra={"task_count": len(tasks), "decision_count": len(decisions)})

        for decision in decisions:
            await self._deliver(decision, now)

        return decisions

    async def run_job(self, job_name: str) -> list[str]:
        if not self._settings.has_vikunja_credentials:
            logger.warning("vikunja_credentials_missing", extra={"job": job_name})
            return []

        tasks = await self._vikunja.list_open_tasks(limit=self._settings.max_tasks_per_scan)
        now = datetime.now(timezone.utc)
        messages: list[str] = []

        if job_name == "morning-planning":
            top = tasks[:3]
            body = (
                "Morning planning check-in:\n"
                + ("\n".join(f"- {task.title}" for task in top) if top else "No open tasks found.")
                + "\nReply with START <task id>, SNOOZE 15, BLOCKED, or BREAK IT DOWN."
            )
            await self._send_telegram_primary(body)
            messages.append(body)
            await self._record_daily_summary(now.date(), planned_tasks=len(top), completed_tasks=0, avoided_tasks=0, generated_summary=body)
        elif job_name == "daily-summary":
            overdue = [task.title for task in tasks if task.due_date and task.due_date < now][:5]
            body = "Midday check-in: " + (", ".join(overdue) if overdue else "No overdue tasks right now.")
            await self._send_telegram_primary(body)
            messages.append(body)
            await self._record_daily_summary(now.date(), planned_tasks=min(3, len(tasks)), completed_tasks=0, avoided_tasks=len(overdue), generated_summary=body)
        elif job_name == "end-of-day-reflection":
            body = "Evening reflection: What moved forward today, and what is your first step tomorrow morning?"
            await self._send_telegram_primary(body)
            messages.append(body)
        elif job_name == "weekly-review":
            await self._run_weekly_review(messages)

        return messages

    async def _run_weekly_review(self, messages: list[str]) -> None:
        if self._postgres is None:
            return
        stats = await self._postgres.weekly_stats()
        stats_text = (
            f"Week start: {stats.get('week_start')}\n"
            f"Completed: {stats.get('tasks_completed', 0)}\n"
            f"Avoided: {stats.get('tasks_avoided', 0)}\n"
            f"Common blockers: {stats.get('common_blockers', [])}"
        )

        summary_text = stats_text
        adjustments = "Try smaller start steps, schedule focus blocks at your best hour, and mark blockers early."
        if self._agent_service is not None:
            prompt = (
                "Generate a concise weekly reflection and 1-3 concrete adjustments based on this stats block:\n"
                + stats_text
            )
            try:
                summary_text = await self._agent_service.coach_message(task_id=0, message=prompt)
            except Exception as exc:  # noqa: BLE001
                logger.warning("weekly_summary_generation_failed", extra={"error": str(exc)})

        await self._send_telegram_primary(summary_text)
        week_start_raw = str(stats.get("week_start") or date.today().isoformat())
        await self._postgres.upsert_weekly_summary(
            week_start=date.fromisoformat(week_start_raw),
            stats_json=stats,
            generated_summary=summary_text,
            recommended_adjustments=adjustments,
        )
        postgres_event_writes_total.inc()
        messages.append(summary_text)

    async def _record_daily_summary(
        self,
        summary_date: date,
        planned_tasks: int,
        completed_tasks: int,
        avoided_tasks: int,
        generated_summary: str,
    ) -> None:
        if self._postgres is None:
            return
        await self._postgres.upsert_daily_summary(
            summary_date=summary_date,
            planned_tasks=planned_tasks,
            completed_tasks=completed_tasks,
            avoided_tasks=avoided_tasks,
            generated_summary=generated_summary,
        )
        postgres_event_writes_total.inc()

    async def _send_telegram_primary(self, text: str) -> None:
        if self._telegram is None or not self._telegram.enabled:
            return
        chat_ids: list[int] = []
        if self._postgres is not None:
            chat_ids = await self._postgres.list_recent_chat_ids(minutes=60 * 24 * 7)
            redis_state_reads_total.inc()
        if not chat_ids and self._settings.telegram_primary_chat_id:
            chat_ids = [self._settings.telegram_primary_chat_id]

        for chat_id in dict.fromkeys(chat_ids):
            await self._telegram.send_message(chat_id=chat_id, text=text)

    async def _deliver(self, decision: NudgeDecision, now: datetime) -> None:
        body = await self._coach.compose(decision)
        channel = self._select_channel(decision)

        if channel == "telegram":
            await self._send_telegram_primary(f"{decision.title}: {body}")
        else:
            try:
                await self._ntfy.publish(
                    decision.topic,
                    body=body,
                    title=decision.title,
                    priority=decision.priority,
                    tags=[decision.reason],
                )
            except Exception as exc:  # noqa: BLE001
                logger.warning("ntfy_publish_failed: %s", exc)
                return

        history = await self._state.record_sent(
            decision.task_id,
            decision.reason,
            now,
            cooldown_minutes=self._settings.nudge_cooldown_minutes,
        )
        redis_state_writes_total.inc()
        nudges_sent_total.labels(channel=channel, nudge_type=decision.reason).inc()

        if self._postgres is not None:
            await self._postgres.record_nudge_event(
                task_id=decision.task_id,
                nudge_type=decision.reason,
                response_type=None,
                channel=channel,
                metadata=decision.metadata,
            )
            postgres_event_writes_total.inc()

        logger.info(
            "nudge_sent",
            extra={
                "task_id": decision.task_id,
                "reason": decision.reason,
                "sent_count": history.sent_count,
                "channel": channel,
                "event_type": "nudge_sent",
            },
        )

        if decision.escalate_to_chat and self._agent_service is not None:
            prompt = (
                f"The task '{decision.title}' triggered a coaching escalation because of {decision.reason}. "
                "Respond like a calm coach and ask one short question that helps the user move."
            )
            try:
                reply = await self._agent_service.coach_message(task_id=decision.task_id, message=prompt)
                await self._send_telegram_primary(reply)
            except Exception as exc:  # noqa: BLE001
                logger.warning("coach_escalation_failed", extra={"task_id": decision.task_id, "error": str(exc)})

    def _select_channel(self, decision: NudgeDecision) -> str:
        # Explicit channel policy: Telegram for conversational loops, ntfy for interrupts.
        if decision.reason in {"repeated_drift", "inactive_in_progress"}:
            return "telegram"
        if decision.reason in {"overdue", "due_soon", "start_window_missed"}:
            return "ntfy"
        return "telegram"
