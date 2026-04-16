from __future__ import annotations

import json
import logging
from datetime import date, datetime, timedelta, timezone
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

CREATE TABLE IF NOT EXISTS nudge_event (
    id BIGSERIAL PRIMARY KEY,
    task_id BIGINT,
    event_ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    nudge_type TEXT NOT NULL,
    response_type TEXT,
    channel TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

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

    async def record_nudge_event(
        self,
        task_id: int | None,
        nudge_type: str,
        response_type: str | None,
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

    async def upsert_daily_summary(
        self,
        summary_date: date,
        planned_tasks: int,
        completed_tasks: int,
        avoided_tasks: int,
        generated_summary: str,
    ) -> None:
        if self._pool is None:
            return
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO daily_summary (summary_date, planned_tasks, completed_tasks, avoided_tasks, generated_summary)
                VALUES ($1, $2, $3, $4, $5)
                ON CONFLICT (summary_date)
                DO UPDATE SET
                    planned_tasks = EXCLUDED.planned_tasks,
                    completed_tasks = EXCLUDED.completed_tasks,
                    avoided_tasks = EXCLUDED.avoided_tasks,
                    generated_summary = EXCLUDED.generated_summary
                """,
                summary_date,
                planned_tasks,
                completed_tasks,
                avoided_tasks,
                generated_summary,
            )

    async def upsert_weekly_summary(
        self,
        week_start: date,
        stats_json: dict[str, Any],
        generated_summary: str,
        recommended_adjustments: str,
    ) -> None:
        if self._pool is None:
            return
        async with self._pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO weekly_summary (week_start, stats_json, generated_summary, recommended_adjustments)
                VALUES ($1, $2::jsonb, $3, $4)
                ON CONFLICT (week_start)
                DO UPDATE SET
                    stats_json = EXCLUDED.stats_json,
                    generated_summary = EXCLUDED.generated_summary,
                    recommended_adjustments = EXCLUDED.recommended_adjustments
                """,
                week_start,
                json.dumps(stats_json),
                generated_summary,
                recommended_adjustments,
            )

    async def recent_learning_snapshot(self, days: int = 14) -> dict[str, Any]:
        if self._pool is None:
            return {}
        async with self._pool.acquire() as conn:
            duration_row = await conn.fetchrow(
                """
                SELECT AVG(actual_duration_minutes::float / NULLIF(estimated_duration_minutes, 0)) AS estimate_ratio
                FROM task_execution
                WHERE started_at >= NOW() - ($1::text || ' days')::interval
                  AND estimated_duration_minutes IS NOT NULL
                  AND actual_duration_minutes IS NOT NULL
                """,
                days,
            )
            ignore_rows = await conn.fetch(
                """
                SELECT task_id, COUNT(*) AS ignored_count
                FROM nudge_event
                WHERE event_ts >= NOW() - ($1::text || ' days')::interval
                  AND response_type IN ('ignored', 'snoozed')
                  AND task_id IS NOT NULL
                GROUP BY task_id
                HAVING COUNT(*) >= 2
                ORDER BY ignored_count DESC
                LIMIT 20
                """,
                days,
            )
            hour_rows = await conn.fetch(
                """
                SELECT EXTRACT(HOUR FROM started_at) AS hour_bucket, COUNT(*) AS starts
                FROM task_execution
                WHERE started_at >= NOW() - ($1::text || ' days')::interval
                  AND started_at IS NOT NULL
                GROUP BY hour_bucket
                ORDER BY starts DESC
                LIMIT 5
                """,
                days,
            )

        return {
            "estimate_ratio": float(duration_row["estimate_ratio"] or 1.0),
            "high_friction_tasks": [int(r["task_id"]) for r in ignore_rows],
            "top_start_hours": [int(r["hour_bucket"]) for r in hour_rows],
        }

    async def weekly_stats(self) -> dict[str, Any]:
        if self._pool is None:
            return {}
        now = datetime.now(timezone.utc)
        week_start = (now - timedelta(days=now.weekday())).date()
        async with self._pool.acquire() as conn:
            completed = await conn.fetchval(
                """
                SELECT COUNT(*)
                FROM task_execution
                WHERE completion_status = 'completed'
                  AND completed_at >= $1
                """,
                week_start,
            )
            avoided = await conn.fetchval(
                """
                SELECT COUNT(*)
                FROM nudge_event
                WHERE event_ts >= $1
                  AND response_type IN ('ignored', 'snoozed', 'blocked', 'overwhelmed')
                """,
                week_start,
            )
            blockers = await conn.fetch(
                """
                SELECT signal_type, COUNT(*) AS c
                FROM user_signal
                WHERE event_ts >= $1
                GROUP BY signal_type
                ORDER BY c DESC
                LIMIT 5
                """,
                week_start,
            )

        return {
            "week_start": str(week_start),
            "tasks_completed": int(completed or 0),
            "tasks_avoided": int(avoided or 0),
            "common_blockers": [{"signal": row["signal_type"], "count": int(row["c"])} for row in blockers],
        }

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
