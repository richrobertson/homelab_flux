from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any

from redis.asyncio import Redis

logger = logging.getLogger(__name__)


class RedisSessionStore:
    def __init__(self, redis_url: str, ttl_seconds: int, max_messages: int, key_prefix: str = "tcp") -> None:
        self._redis = Redis.from_url(redis_url, decode_responses=True)
        self._ttl_seconds = ttl_seconds
        self._max_messages = max_messages
        self._key_prefix = key_prefix
        self._lock = asyncio.Lock()

    async def close(self) -> None:
        await self._redis.aclose()

    async def get_messages(self, session_id: str) -> list[dict[str, Any]]:
        key = f"{self._key_prefix}:session:{session_id}"
        raw = await self._redis.get(key)
        if not raw:
            return []
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return []
        if not isinstance(payload, list):
            return []
        return [msg for msg in payload if isinstance(msg, dict)]

    async def append_messages(self, session_id: str, new_messages: list[dict[str, Any]]) -> None:
        async with self._lock:
            existing = await self.get_messages(session_id)
            merged = [*existing, *new_messages]
            merged = merged[-self._max_messages :]
            key = f"{self._key_prefix}:session:{session_id}"
            await self._redis.set(key, json.dumps(merged), ex=self._ttl_seconds)

    async def clear(self, session_id: str) -> None:
        key = f"{self._key_prefix}:session:{session_id}"
        await self._redis.delete(key)

    async def update_telegram_session(
        self,
        chat_id: int,
        message_text: str,
        signal_type: str | None,
        user_id: str | None,
    ) -> None:
        key = f"{self._key_prefix}:telegram_session:{chat_id}"
        now = int(time.time())
        fields = {
            "chat_id": str(chat_id),
            "last_message": message_text[:200],
            "last_signal": signal_type or "none",
            "last_user_id": user_id or "",
            "last_seen": str(now),
        }
        await self._redis.hset(key, mapping=fields)
        await self._redis.expire(key, self._ttl_seconds)

    async def set_user_state(
        self,
        user_id: str,
        current_energy: str | None,
        last_signal: str | None,
        focus_task_id: int | None,
        ttl_seconds: int = 7200,
    ) -> None:
        key = f"{self._key_prefix}:user_state:{user_id}"
        mapping = {
            "current_energy": current_energy or "unknown",
            "last_signal": last_signal or "none",
            "current_focus_task": str(focus_task_id or ""),
            "updated_at": str(int(time.time())),
        }
        await self._redis.hset(key, mapping=mapping)
        await self._redis.expire(key, ttl_seconds)

    async def ping(self) -> bool:
        try:
            return bool(await self._redis.ping())
        except Exception:  # noqa: BLE001
            logger.warning("redis_ping_failed")
            return False
