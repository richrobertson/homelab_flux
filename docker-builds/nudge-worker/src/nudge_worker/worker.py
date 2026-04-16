from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from nudge_worker.clients.agent_service_client import AgentServiceClient
from nudge_worker.clients.ntfy_client import NtfyClient
from nudge_worker.clients.vikunja_client import VikunjaClient
from nudge_worker.coach import CoachingComposer
from nudge_worker.config import Settings
from nudge_worker.decision_engine import DecisionEngine
from nudge_worker.models import NudgeDecision
from nudge_worker.state_store import InMemoryNudgeStateStore

logger = logging.getLogger(__name__)


class NudgeWorker:
    def __init__(
        self,
        settings: Settings,
        vikunja_client: VikunjaClient,
        ntfy_client: NtfyClient,
        state_store: InMemoryNudgeStateStore,
        coach: CoachingComposer,
        agent_service_client: AgentServiceClient | None = None,
    ) -> None:
        self._settings = settings
        self._vikunja = vikunja_client
        self._ntfy = ntfy_client
        self._state = state_store
        self._engine = DecisionEngine(settings, state_store)
        self._coach = coach
        self._agent_service = agent_service_client

    async def run_forever(self) -> None:
        while True:
            try:
                await self.run_once()
            except Exception as exc:  # noqa: BLE001
                logger.warning("nudge_scan_failed", extra={"error": str(exc)})
            await asyncio.sleep(self._settings.scan_interval_seconds)

    async def run_once(self) -> list[NudgeDecision]:
        if not self._settings.has_vikunja_credentials:
            logger.warning("vikunja_credentials_missing")
            return []

        now = datetime.now(timezone.utc)
        tasks = await self._vikunja.list_open_tasks(limit=self._settings.max_tasks_per_scan)
        decisions = self._engine.decide(tasks, now=now)
        logger.info("nudge_scan_complete", extra={"task_count": len(tasks), "decision_count": len(decisions)})

        for decision in decisions:
            await self._deliver(decision, now)

        return decisions

    async def run_job(self, job_name: str) -> list[str]:
        if not self._settings.has_vikunja_credentials:
            logger.warning("vikunja_credentials_missing", extra={"job": job_name})
            return []

        tasks = await self._vikunja.list_open_tasks(limit=self._settings.max_tasks_per_scan)
        messages: list[str] = []

        if job_name == "morning-planning":
            top = tasks[:3]
            body = "Morning plan: " + "; ".join(task.title for task in top) if top else "Morning plan: no open tasks."
            await self._ntfy.publish(self._settings.ntfy_focus_topic, body=body, title="Morning planning", priority="default")
            messages.append(body)
        elif job_name == "daily-summary":
            overdue = [task.title for task in tasks if task.due_date and task.due_date < datetime.now(timezone.utc)][:5]
            body = "Daily summary: " + (", ".join(overdue) if overdue else "no overdue tasks right now.")
            await self._ntfy.publish(self._settings.ntfy_reminders_topic, body=body, title="Daily summary", priority="default")
            messages.append(body)
        elif job_name == "end-of-day-reflection":
            body = "End-of-day reflection: What moved forward today, and what should be your first step tomorrow?"
            await self._ntfy.publish(self._settings.ntfy_focus_topic, body=body, title="Reflection", priority="default")
            messages.append(body)

        return messages

    async def _deliver(self, decision: NudgeDecision, now: datetime) -> None:
        body = await self._coach.compose(decision)
        await self._ntfy.publish(
            decision.topic,
            body=body,
            title=decision.title,
            priority=decision.priority,
            tags=[decision.reason],
        )
        history = self._state.record_sent(decision.task_id, decision.reason, now)
        logger.info(
            "nudge_sent",
            extra={"task_id": decision.task_id, "reason": decision.reason, "sent_count": history.sent_count},
        )

        if decision.escalate_to_chat and self._agent_service is not None:
            prompt = (
                f"The task '{decision.title}' triggered a coaching escalation because of {decision.reason}. "
                "Respond like a calm coach and ask one short question that helps the user move."
            )
            try:
                reply = await self._agent_service.coach_message(task_id=decision.task_id, message=prompt)
                await self._ntfy.publish(
                    self._settings.ntfy_escalation_topic,
                    body=reply,
                    title=f"Coach follow-up: {decision.title}",
                    priority="high",
                    tags=["coach"],
                )
            except Exception as exc:  # noqa: BLE001
                logger.warning("coach_escalation_failed", extra={"task_id": decision.task_id, "error": str(exc)})
