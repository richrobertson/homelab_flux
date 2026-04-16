from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass
class BehaviorAssessment:
    category: str
    coaching_instruction: str
    preferred_tool: str | None = None
    should_soften_tone: bool = False
    suggest_starter_step: bool = False


def assess_behavior(message: str) -> BehaviorAssessment | None:
    text = message.lower().strip()

    if _matches(text, [r"\boverwhelm", r"too much", r"spiral", r"can'?t keep up"]):
        return BehaviorAssessment(
            category="overwhelmed",
            coaching_instruction="Acknowledge overload, reduce scope, and prefer breaking work into smaller steps.",
            preferred_tool="break_down_task",
            should_soften_tone=True,
            suggest_starter_step=True,
        )

    if _matches(text, [r"tired", r"don'?t feel good", r"exhausted", r"sick", r"burned out"]):
        return BehaviorAssessment(
            category="low_energy",
            coaching_instruction="Soften the tone, reduce pressure, and offer rescheduling or a lighter version of the task.",
            should_soften_tone=True,
        )

    if _matches(text, [r"avoiding", r"putting this off", r"can'?t focus", r"stuck starting", r"blocked"]):
        return BehaviorAssessment(
            category="avoidance",
            coaching_instruction="Suggest a 5-minute starter action and avoid abstract advice.",
            preferred_tool="suggest_next_task",
            suggest_starter_step=True,
        )

    if _matches(text, [r"push this", r"reschedule", r"move this", r"not today"]):
        return BehaviorAssessment(
            category="reschedule",
            coaching_instruction="Help the user deliberately reschedule the task instead of silently dropping it.",
            should_soften_tone=True,
        )

    if _matches(text, [r"break (it|this) down", r"smaller steps", r"too big"]):
        return BehaviorAssessment(
            category="breakdown",
            coaching_instruction="Break the task into short, concrete sub-steps.",
            preferred_tool="break_down_task",
        )

    return None


def build_behavior_system_hint(assessment: BehaviorAssessment) -> str:
    hints = [
        f"Behavior category detected: {assessment.category}.",
        assessment.coaching_instruction,
    ]
    if assessment.preferred_tool:
        hints.append(f"Prefer tool usage: {assessment.preferred_tool}.")
    if assessment.should_soften_tone:
        hints.append("Use a softer, coach-like tone.")
    if assessment.suggest_starter_step:
        hints.append("Offer a 5-minute starter step if appropriate.")
    return " ".join(hints)


TASK_ID_PATTERN = re.compile(r"(?:task\s+#?)(\d+)", re.IGNORECASE)


def extract_task_id(message: str) -> int | None:
    match = TASK_ID_PATTERN.search(message)
    if not match:
        return None
    return int(match.group(1))


def _matches(text: str, patterns: list[str]) -> bool:
    return any(re.search(pattern, text) for pattern in patterns)
