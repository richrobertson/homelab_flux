from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Optional


@dataclass
class NudgeDecision:
    task_id: int
    title: str
    reason: str
    topic: str
    priority: str
    body: str
    metadata: dict[str, Any] = field(default_factory=dict)
    escalate_to_chat: bool = False


@dataclass
class TaskSnapshot:
    task_id: int
    title: str
    due_date: Optional[datetime]
    start_date: Optional[datetime]
    updated_at: Optional[datetime]
    done: bool
    percent_done: float
    priority: int
    raw: dict[str, Any]


@dataclass
class NudgeHistory:
    last_sent_at: Optional[datetime] = None
    last_reason: Optional[str] = None
    sent_count: int = 0
