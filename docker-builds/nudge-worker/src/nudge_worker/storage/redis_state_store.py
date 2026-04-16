from __future__ import annotations

import json
import logging
from datetime import datetime, timedelta, timezone

from redis.asyncio import Redis

from nudge_worker.models import NudgeHistory

logger = logging.getLogger(__name__)


class RedisNudgeStateStore:
    def __init__(self, redis_url: str, key_prefix: str = "tcp") -> None:
        self._redis = Redis.from_url(redis_url, decode_responses=True)
        self._key_prefix = key_prefix

    async def close(self) -> None:
        await self._redis.aclose()

    async def should_send(self, task_id: int, reason: str, cooldown_minutes: int, now: datetime) -> bool:
        manual_snooze_key = f"{self._key_prefix}:manual_snooze:{task_id}"
        if await self._redis.exists(manual_snooze_key):
            return False
        cooldown_key = f"{self._key_prefix}:nudge_cooldown:{task_id}:{reason}"
        if await self._redis.exists(cooldown_key):
            return False

        history = await self.get(task_id)
        if not history.last_sent_at:
            return True
        if history.last_reason != reason:
            return True
        return now - history.last_sent_at >= timedelta(minutes=cooldown_minutes)

    async def record_sent(self, task_id: int, reason: str, now: datetime, cooldown_minutes: int) -> NudgeHistory:
        history_key = f"{self._key_prefix}:task_session:{task_id}"
        current = await self.get(task_id)
        sent_count = current.sent_count + 1
        await self._redis.hset(
            history_key,
            mapping={
                "task_id": str(task_id),
                "state": "active",
                "last_nudge_type": reason,
                "last_activity_time": now.astimezone(timezone.utc).isoformat(),
                "nudges_sent": str(sent_count),
            },
        )
        await self._redis.expire(history_key, 172800)

        cooldown_key = f"{self._key_prefix}:nudge_cooldown:{task_id}:{reason}"
        await self._redis.set(cooldown_key, "1", ex=max(60, cooldown_minutes * 60))

        return NudgeHistory(
            last_sent_at=now.astimezone(timezone.utc),
            last_reason=reason,
            sent_count=sent_count,
        )

    async def get(self, task_id: int) -> NudgeHistory:
        history_key = f"{self._key_prefix}:task_session:{task_id}"
        data = await self._redis.hgetall(history_key)
        if not data:
            return NudgeHistory()

        last_sent_at = None
        raw_last = data.get("last_activity_time")
        if raw_last:
            try:
                last_sent_at = datetime.fromisoformat(raw_last.replace("Z", "+00:00"))
            except ValueError:
                last_sent_at = None

        sent_count = 0
        try:
            sent_count = int(data.get("nudges_sent") or 0)
        except ValueError:
            sent_count = 0

        return NudgeHistory(last_sent_at=last_sent_at, last_reason=data.get("last_nudge_type"), sent_count=sent_count)

    async def set_telegram_context(self, chat_id: int, payload: dict[str, str], ttl_seconds: int = 7200) -> None:
        key = f"{self._key_prefix}:telegram_session:{chat_id}"
        await self._redis.hset(key, mapping=payload)
        await self._redis.expire(key, ttl_seconds)

    async def set_user_state(self, user_id: str, payload: dict[str, str], ttl_seconds: int = 7200) -> None:
        key = f"{self._key_prefix}:user_state:{user_id}"
        await self._redis.hset(key, mapping=payload)
        await self._redis.expire(key, ttl_seconds)

    async def get_user_state(self, user_id: str) -> dict[str, str]:
        key = f"{self._key_prefix}:user_state:{user_id}"
        data = await self._redis.hgetall(key)
        return {str(k): str(v) for k, v in data.items()}

    async def get_telegram_context(self, chat_id: int) -> dict[str, str]:
        key = f"{self._key_prefix}:telegram_context:{chat_id}"
        data = await self._redis.hgetall(key)
        return {str(k): str(v) for k, v in data.items()}

    async def is_telegram_active(self, chat_id: int, within_seconds: int = 900) -> bool:
        context = await self.get_telegram_context(chat_id)
        last_seen = context.get("updated_at") or context.get("last_seen")
        if not last_seen:
            return False
        try:
            return int(datetime.now(timezone.utc).timestamp()) - int(last_seen) <= within_seconds
        except ValueError:
            return False

    async def ping(self) -> bool:
        try:
            return bool(await self._redis.ping())
        except Exception:  # noqa: BLE001
            logger.warning("redis_ping_failed")
            return False
