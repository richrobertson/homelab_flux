from __future__ import annotations

import argparse
import asyncio
import logging

from nudge_worker.clients.agent_service_client import AgentServiceClient
from nudge_worker.clients.ntfy_client import NtfyClient
from nudge_worker.clients.openai_client import OpenAIClient
from nudge_worker.clients.telegram_client import TelegramClient
from nudge_worker.clients.vikunja_client import VikunjaClient
from nudge_worker.coach import CoachingComposer
from nudge_worker.config import get_settings
from nudge_worker.logging_config import configure_logging
from nudge_worker.metrics import start_metrics_server
from nudge_worker.state_store import InMemoryNudgeStateStore
from nudge_worker.storage.postgres_store import PostgresStore
from nudge_worker.storage.redis_state_store import RedisNudgeStateStore
from nudge_worker.worker import NudgeWorker


async def _async_main() -> None:
    parser = argparse.ArgumentParser(description="nudge-worker")
    parser.add_argument("--mode", choices=["worker", "job"], default="worker")
    parser.add_argument(
        "--job",
        choices=["morning-planning", "daily-summary", "end-of-day-reflection", "weekly-review"],
        default="daily-summary",
    )
    args = parser.parse_args()

    settings = get_settings()
    configure_logging(settings.log_level)
    logger = logging.getLogger(__name__)

    vikunja_client = VikunjaClient(settings)
    ntfy_client = NtfyClient(settings)
    telegram_client = TelegramClient(bot_token=settings.telegram_bot_token)
    postgres_store = PostgresStore(settings.effective_postgres_dsn)
    await postgres_store.initialize()

    if settings.redis_url:
        state_store: object = RedisNudgeStateStore(redis_url=settings.redis_url, key_prefix=settings.redis_key_prefix)
    else:
        state_store = InMemoryNudgeStateStore()

    openai_client = OpenAIClient(settings) if settings.has_openai_credentials else None
    coach = CoachingComposer(openai_client=openai_client)
    agent_client = AgentServiceClient(settings) if settings.agent_service_base_url else None

    if args.mode == "worker":
        start_metrics_server(settings.metrics_port)

    worker = NudgeWorker(
        settings=settings,
        vikunja_client=vikunja_client,
        ntfy_client=ntfy_client,
        state_store=state_store,
        coach=coach,
        postgres_store=postgres_store,
        telegram_client=telegram_client,
        agent_service_client=agent_client,
    )

    try:
        if args.mode == "job":
            messages = await worker.run_job(args.job)
            logger.info("job_complete", extra={"job": args.job, "message_count": len(messages)})
        else:
            await worker.run_forever()
    finally:
        await vikunja_client.close()
        await ntfy_client.close()
        await telegram_client.close()
        await postgres_store.close()
        if openai_client is not None:
            await openai_client.close()
        if agent_client is not None:
            await agent_client.close()
        if hasattr(state_store, "close"):
            await state_store.close()


def main() -> None:
    asyncio.run(_async_main())


if __name__ == "__main__":
    main()
