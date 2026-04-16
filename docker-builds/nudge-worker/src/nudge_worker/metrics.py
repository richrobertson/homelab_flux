from __future__ import annotations

from prometheus_client import Counter, Gauge, Histogram, start_http_server

nudges_sent_total = Counter(
    "nudges_sent_total",
    "Total nudges sent",
    ["channel", "nudge_type"],
)

nudges_ignored_total = Counter(
    "nudges_ignored_total",
    "Estimated ignored nudges",
)

tasks_completed_total = Counter(
    "tasks_completed_total",
    "Tasks marked completed by worker flows",
)

task_start_delay_seconds = Histogram(
    "task_start_delay_seconds",
    "Task start delay in seconds",
    buckets=(60, 300, 600, 900, 1800, 3600, 7200, 14400, 28800),
)

redis_state_reads_total = Counter(
    "redis_state_reads_total",
    "Redis read operations in nudge-worker",
)

redis_state_writes_total = Counter(
    "redis_state_writes_total",
    "Redis write operations in nudge-worker",
)

postgres_event_writes_total = Counter(
    "postgres_event_writes_total",
    "Postgres writes in nudge-worker",
)

active_task_sessions = Gauge(
    "active_task_sessions",
    "Current active task sessions known to nudge-worker",
)


def start_metrics_server(port: int) -> None:
    start_http_server(port)
