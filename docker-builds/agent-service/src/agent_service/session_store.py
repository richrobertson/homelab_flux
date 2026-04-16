import asyncio
import time
from collections import defaultdict
from dataclasses import dataclass
from typing import Any


@dataclass
class SessionState:
    messages: list[dict[str, Any]]
    updated_at: float


class InMemorySessionStore:
    def __init__(self, ttl_seconds: int, max_messages: int) -> None:
        self._ttl_seconds = ttl_seconds
        self._max_messages = max_messages
        self._sessions: dict[str, SessionState] = defaultdict(
            lambda: SessionState(messages=[], updated_at=time.time())
        )
        self._lock = asyncio.Lock()

    async def get_messages(self, session_id: str) -> list[dict[str, Any]]:
        async with self._lock:
            self._gc_locked()
            state = self._sessions.get(session_id)
            return list(state.messages) if state else []

    async def append_messages(self, session_id: str, new_messages: list[dict[str, Any]]) -> None:
        async with self._lock:
            self._gc_locked()
            state = self._sessions[session_id]
            state.messages.extend(new_messages)
            state.messages = state.messages[-self._max_messages :]
            state.updated_at = time.time()

    async def clear(self, session_id: str) -> None:
        async with self._lock:
            self._sessions.pop(session_id, None)

    def _gc_locked(self) -> None:
        now = time.time()
        expired = [
            key
            for key, state in self._sessions.items()
            if now - state.updated_at > self._ttl_seconds
        ]
        for key in expired:
            del self._sessions[key]
