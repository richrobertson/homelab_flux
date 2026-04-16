from __future__ import annotations

from typing import Any

CALLBACK_PART_SEPARATOR = "|"
CALLBACK_KEY_VALUE_SEPARATOR = ":"


def build_callback_data(action: str, task_id: int, **metadata: int | str | None) -> str:
    parts = [f"action:{action}", f"task_id:{task_id}"]
    for key, value in metadata.items():
        if value is None:
            continue
        parts.append(f"{key}:{value}")
    payload = CALLBACK_PART_SEPARATOR.join(parts)
    if len(payload) > 64:
        raise ValueError(f"callback_data exceeds Telegram limit: {payload}")
    return payload


def parse_callback_data(data: str) -> dict[str, str]:
    payload: dict[str, str] = {}
    for item in (data or "").split(CALLBACK_PART_SEPARATOR):
        if CALLBACK_KEY_VALUE_SEPARATOR not in item:
            continue
        key, value = item.split(CALLBACK_KEY_VALUE_SEPARATOR, 1)
        payload[key] = value
    return payload


def build_task_keyboard(message_type: str, task_id: int) -> dict[str, list[list[dict[str, str]]]]:
    if message_type == "recovery":
        rows = [
            [
                {"text": "BREAK IT DOWN", "callback_data": build_callback_data("break_down", task_id)},
                {"text": "SNOOZE 30", "callback_data": build_callback_data("snooze", task_id, minutes=30)},
            ],
            [
                {"text": "START", "callback_data": build_callback_data("start", task_id)},
            ],
        ]
    elif message_type in {"check_in", "completion_check"}:
        rows = [
            [
                {"text": "DONE", "callback_data": build_callback_data("done", task_id)},
                {"text": "SNOOZE 15", "callback_data": build_callback_data("snooze", task_id, minutes=15)},
            ],
            [
                {"text": "BLOCKED", "callback_data": build_callback_data("blocked", task_id)},
                {"text": "BREAK IT DOWN", "callback_data": build_callback_data("break_down", task_id)},
            ],
        ]
    else:
        rows = [
            [
                {"text": "START", "callback_data": build_callback_data("start", task_id)},
                {"text": "SNOOZE 15", "callback_data": build_callback_data("snooze", task_id, minutes=15)},
            ],
            [
                {"text": "SNOOZE 30", "callback_data": build_callback_data("snooze", task_id, minutes=30)},
                {"text": "BLOCKED", "callback_data": build_callback_data("blocked", task_id)},
            ],
            [
                {"text": "BREAK IT DOWN", "callback_data": build_callback_data("break_down", task_id)},
                {"text": "DONE", "callback_data": build_callback_data("done", task_id)},
            ],
        ]

    return {"inline_keyboard": rows}


def format_task_message(
    *,
    message_type: str,
    task_title: str,
    task_id: int,
    body: str | None = None,
    duration_minutes: int | None = None,
) -> str:
    duration_label = f" ({duration_minutes} min)" if duration_minutes else ""
    header_map = {
        "nudge": "Start",
        "start_prompt": "Start",
        "check_in": "Check-in",
        "recovery": "Recovery",
        "completion_check": "Done?",
    }
    header = header_map.get(message_type, "Task")
    lines = [f"{header}: {task_title}{duration_label}", f"Task #{task_id}"]

    body_map = {
        "nudge": "You planned this for now.",
        "start_prompt": "You planned this for now.",
        "check_in": "You started this recently.",
        "recovery": "Something is getting in the way.",
        "completion_check": "Quick status check.",
    }
    if body:
        lines.append(body.strip())
    else:
        lines.append(body_map.get(message_type, "What do you want to do?"))

    prompt_map = {
        "recovery": "What helps most right now?",
        "check_in": "What do you want to do next?",
        "completion_check": "What do you want to do next?",
    }
    lines.append(prompt_map.get(message_type, "What do you want to do?"))
    return "\n\n".join(lines)


def format_callback_confirmation(action: str, task_title: str, task_id: int, minutes: int | None = None) -> tuple[str, str]:
    if action == "start":
        return (
            f"Started: {task_title}",
            f"Started Task #{task_id}. I will keep context on this one.",
        )
    if action == "snooze":
        label = minutes or 15
        return (
            f"Snoozed: {task_title}",
            f"Okay. I will bring back Task #{task_id} in {label} minutes.",
        )
    if action == "blocked":
        return (
            f"Blocked: {task_title}",
            "What is blocking you? Choose a recovery option below.",
        )
    if action == "break_down":
        return (
            f"Break down: {task_title}",
            f"Here is a smaller way into Task #{task_id}.",
        )
    if action == "done":
        return (
            f"Done: {task_title}",
            f"Marked Task #{task_id} done.",
        )
    return (f"Updated: {task_title}", f"Recorded {action} for Task #{task_id}.")


def build_breakdown_message(task_title: str, task_id: int, steps: list[str]) -> str:
    numbered_steps = "\n".join(f"{index + 1}. {step}" for index, step in enumerate(steps[:4]))
    return (
        f"Break down: {task_title}\n\n"
        f"Task #{task_id}\n\n"
        f"{numbered_steps}\n\n"
        "Want to start now or snooze it briefly?"
    )


def build_task_send_payload(
    *,
    task_id: int,
    task_title: str,
    message_type: str,
    body: str | None = None,
    duration_minutes: int | None = None,
) -> dict[str, Any]:
    return {
        "text": format_task_message(
            message_type=message_type,
            task_title=task_title,
            task_id=task_id,
            body=body,
            duration_minutes=duration_minutes,
        ),
        "task_id": task_id,
        "task_title": task_title,
        "message_type": message_type,
        "reply_markup": build_task_keyboard(message_type, task_id),
    }