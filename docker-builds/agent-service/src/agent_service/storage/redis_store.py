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

    async def get_telegram_context(self, chat_id: int) -> dict[str, str]:
        key = f"{self._key_prefix}:telegram_context:{chat_id}"
        data = await self._redis.hgetall(key)
        return {str(key): str(value) for key, value in data.items()}

    async def update_telegram_context(
        self,
        chat_id: int,
        *,
        user_id: str | None = None,
        active_task_id: int | None = None,
        last_task_id: int | None = None,
        last_action: str | None = None,
        message_type: str | None = None,
        task_title: str | None = None,
        message_id: int | None = None,
        clear_active_task: bool = False,
    ) -> None:
        key = f"{self._key_prefix}:telegram_context:{chat_id}"
        existing = await self.get_telegram_context(chat_id)
        mapping = dict(existing)
        mapping["chat_id"] = str(chat_id)
        mapping["updated_at"] = str(int(time.time()))
        if user_id is not None:
            mapping["user_id"] = user_id
        if clear_active_task:
            mapping["active_task_id"] = ""
        elif active_task_id is not None:
            mapping["active_task_id"] = str(active_task_id)
        if last_task_id is not None:
            mapping["last_task_id"] = str(last_task_id)
        if last_action is not None:
            mapping["last_action"] = last_action
        if message_type is not None:
            mapping["last_message_type"] = message_type
        if task_title is not None:
            mapping["last_task_title"] = task_title[:200]
        if message_id is not None:
            mapping["last_bot_message_id"] = str(message_id)
        await self._redis.hset(key, mapping=mapping)
        await self._redis.expire(key, self._ttl_seconds)

    async def infer_task_id(self, chat_id: int, message_text: str) -> int | None:
        context = await self.get_telegram_context(chat_id)
        if not context:
            return None
        lower = message_text.strip().lower()
        if lower in {"ok", "yes", "start", "push it", "do it", "later", "done", "blocked", "break it down"}:
            active = context.get("active_task_id")
            if active:
                try:
                    return int(active)
                except ValueError:
                    return None
            last_task = context.get("last_task_id")
            if last_task:
                try:
                    return int(last_task)
                except ValueError:
                    return None
        return None

    async def claim_callback(self, callback_id: str, ttl_seconds: int = 300) -> bool:
        key = f"{self._key_prefix}:telegram_callback:{callback_id}"
        return bool(await self._redis.set(key, "1", ex=ttl_seconds, nx=True))

    async def set_manual_snooze(self, task_id: int, minutes: int) -> None:
        key = f"{self._key_prefix}:manual_snooze:{task_id}"
        await self._redis.set(key, str(minutes), ex=max(60, minutes * 60))

    async def get_manual_snooze(self, task_id: int) -> str | None:
        key = f"{self._key_prefix}:manual_snooze:{task_id}"
        value = await self._redis.get(key)
        return str(value) if value is not None else None

    async def set_pending_telegram_attachments(
        self,
        chat_id: int,
        attachments: list[dict[str, str]],
    ) -> None:
        key = f"{self._key_prefix}:telegram_pending_attachments:{chat_id}"
        await self._redis.set(key, json.dumps(attachments), ex=self._ttl_seconds)

    async def get_pending_telegram_attachments(self, chat_id: int) -> list[dict[str, str]]:
        key = f"{self._key_prefix}:telegram_pending_attachments:{chat_id}"
        raw = await self._redis.get(key)
        if not raw:
            return []
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return []
        if not isinstance(payload, list):
            return []
        return [item for item in payload if isinstance(item, dict)]

    async def clear_pending_telegram_attachments(self, chat_id: int) -> None:
        key = f"{self._key_prefix}:telegram_pending_attachments:{chat_id}"
        await self._redis.delete(key)

    async def is_telegram_active(self, chat_id: int, within_seconds: int = 900) -> bool:
        context = await self.get_telegram_context(chat_id)
        last_seen = context.get("updated_at") or context.get("last_seen")
        if not last_seen:
            return False
        try:
            return int(time.time()) - int(last_seen) <= within_seconds
        except ValueError:
            return False

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
