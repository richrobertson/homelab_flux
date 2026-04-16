from __future__ import annotations

from nudge_worker.models import NudgeDecision
from nudge_worker.prompts import NUDGE_SYSTEM_PROMPT


class CoachingComposer:
    def __init__(self, openai_client: object | None = None) -> None:
        self._openai_client = openai_client

    async def compose(self, decision: NudgeDecision) -> str:
        if not self._openai_client or decision.reason not in {"overdue", "repeated_drift", "inactive_in_progress"}:
            return decision.body

        user_prompt = (
            f"Task title: {decision.title}\n"
            f"Reason: {decision.reason}\n"
            f"Draft message: {decision.body}\n"
            f"Metadata: {decision.metadata}"
        )
        rewritten = await self._openai_client.compose_coaching_nudge(NUDGE_SYSTEM_PROMPT, user_prompt)
        return rewritten.strip() or decision.body
