from __future__ import annotations

from prometheus_client import Counter, Histogram, generate_latest

telegram_messages_received_total = Counter(
    "telegram_messages_received_total",
    "Total Telegram messages received by webhook",
)

telegram_messages_sent_total = Counter(
    "telegram_messages_sent_total",
    "Total Telegram messages sent back to Telegram users",
)

postgres_event_writes_total = Counter(
    "postgres_event_writes_total",
    "Number of successful Postgres event writes",
)

redis_state_reads_total = Counter(
    "redis_state_reads_total",
    "Number of Redis reads",
)

redis_state_writes_total = Counter(
    "redis_state_writes_total",
    "Number of Redis writes",
)

chat_request_latency_seconds = Histogram(
    "agent_chat_request_latency_seconds",
    "Latency of chat requests processed by agent-service",
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10),
)


def render_metrics() -> bytes:
    return generate_latest()
