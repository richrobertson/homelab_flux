from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any

import asyncpg

logger = logging.getLogger(__name__)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS task_execution (
    id BIGSERIAL PRIMARY KEY,
    task_id BIGINT NOT NULL,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    estimated_duration_minutes INTEGER,
    actual_duration_minutes INTEGER,
    completion_status TEXT NOT NULL DEFAULT 'active',
    source TEXT NOT NULL DEFAULT 'telegram'
);

CREATE INDEX IF NOT EXISTS idx_task_execution_task_id ON task_execution(task_id);
CREATE INDEX IF NOT EXISTS idx_task_execution_started_at ON task_execution(started_at);

CREATE TABLE IF NOT EXISTS nudge_event (
    id BIGSERIAL PRIMARY KEY,
    task_id BIGINT,
    event_ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    nudge_type TEXT NOT NULL,
    response_type TEXT,
    channel TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_nudge_event_task_id ON nudge_event(task_id);
CREATE INDEX IF NOT EXISTS idx_nudge_event_event_ts ON nudge_event(event_ts);

CREATE TABLE IF NOT EXISTS user_signal (
    id BIGSERIAL PRIMARY KEY,
    event_ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    signal_type TEXT NOT NULL,
    related_task_id BIGINT,
    raw_text TEXT,
    normalized_action TEXT,
    user_id TEXT,
    channel TEXT NOT NULL DEFAULT 'telegram'
);

CREATE INDEX IF NOT EXISTS idx_user_signal_event_ts ON user_signal(event_ts);

CREATE TABLE IF NOT EXISTS daily_summary (
    id BIGSERIAL PRIMARY KEY,
    summary_date DATE NOT NULL UNIQUE,
    planned_tasks INTEGER NOT NULL DEFAULT 0,
    completed_tasks INTEGER NOT NULL DEFAULT 0,
    avoided_tasks INTEGER NOT NULL DEFAULT 0,
    generated_summary TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS weekly_summary (
    id BIGSERIAL PRIMARY KEY,
    week_start DATE NOT NULL UNIQUE,
    stats_json JSONB NOT NULL,
    generated_summary TEXT NOT NULL,
    recommended_adjustments TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS telegram_chat_state (
    chat_id BIGINT PRIMARY KEY,
    last_seen_at TIMESTAMPTZ NOT NULL,
    last_user_id TEXT,
    username TEXT,
    first_name TEXT
);
"""


class PostgresStore:
    def __init__(self, dsn: str | None) -> None:
        self._dsn = (dsn or "").strip()
        self._pool: asyncpg.Pool | None = None

    @property
    def enabled(self) -> bool:
        return bool(self._dsn)

    async def initialize(self) -> None:
        if not self.enabled:
            logger.warning("postgres_disabled")
            return
        self._pool = await asyncpg.create_pool(dsn=self._dsn, min_size=1, max_size=6)
        async with self._pool.acquire() as conn:
            await conn.execute(SCHEMA_SQL)
        logger.info("postgres_schema_ready")

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()

    async def record_chat_seen(
        self,
        chat_id: int,
        user_id: str | None,
        username: str | None,
        first_name: str | None,
    ) -> None:
        if self._pool is None:
            return
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO telegram_chat_state (chat_id, last_seen_at, last_user_id, username, first_name)
                VALUES ($1, NOW(), $2, $3, $4)
                ON CONFLICT (chat_id)
                DO UPDATE SET
                  last_seen_at = EXCLUDED.last_seen_at,
                  last_user_id = EXCLUDED.last_user_id,
                  username = EXCLUDED.username,
                  first_name = EXCLUDED.first_name
                """,
                chat_id,
                user_id,
                username,
                first_name,
            )

    async def record_user_signal(
        self,
        signal_type: str,
        raw_text: str,
        normalized_action: str,
        related_task_id: int | None,
        user_id: str | None,
    ) -> None:
        if self._pool is None:
            return
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO user_signal (signal_type, related_task_id, raw_text, normalized_action, user_id, channel)
                VALUES ($1, $2, $3, $4, $5, 'telegram')
                """,
                signal_type,
                related_task_id,
                raw_text,
                normalized_action,
                user_id,
            )

    async def record_nudge_response(
        self,
        task_id: int | None,
        nudge_type: str,
        response_type: str,
        channel: str,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        if self._pool is None:
            return
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO nudge_event (task_id, nudge_type, response_type, channel, metadata)
                VALUES ($1, $2, $3, $4, $5::jsonb)
                """,
                task_id,
                nudge_type,
                response_type,
                channel,
                json.dumps(metadata or {}),
            )

    async def start_task_execution(self, task_id: int, estimated_duration_minutes: int | None = None) -> None:
        if self._pool is None:
            return
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO task_execution (task_id, started_at, estimated_duration_minutes, completion_status)
                VALUES ($1, NOW(), $2, 'started')
                """,
                task_id,
                estimated_duration_minutes,
            )

    async def complete_task_execution(self, task_id: int, status: str = "completed") -> None:
        if self._pool is None:
            return
        now = datetime.now(timezone.utc)
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                UPDATE task_execution
                SET completed_at = $2,
                    completion_status = $3,
                    actual_duration_minutes = GREATEST(
                        1,
                        EXTRACT(EPOCH FROM ($2 - started_at))::INT / 60
                    )
                WHERE id = (
                    SELECT id
                    FROM task_execution
                    WHERE task_id = $1
                    ORDER BY id DESC
                    LIMIT 1
                )
                """,
                task_id,
                now,
                status,
            )

    async def list_recent_chat_ids(self, minutes: int = 10080) -> list[int]:
        if self._pool is None:
            return []
        async with self._pool.acquire() as conn:
            rows = await conn.fetch(
                """
                SELECT chat_id
                FROM telegram_chat_state
                WHERE last_seen_at >= NOW() - ($1::text || ' minutes')::interval
                ORDER BY last_seen_at DESC
                """,
                minutes,
            )
        return [int(row["chat_id"]) for row in rows]
