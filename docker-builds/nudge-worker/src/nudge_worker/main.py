from __future__ import annotations

import argparse
import asyncio
import logging

from nudge_worker.clients.agent_service_client import AgentServiceClient
from nudge_worker.clients.ntfy_client import NtfyClient
from nudge_worker.clients.openai_client import OpenAIClient
from nudge_worker.clients.vikunja_client import VikunjaClient
from nudge_worker.coach import CoachingComposer
from nudge_worker.config import get_settings
from nudge_worker.logging_config import configure_logging
from nudge_worker.state_store import InMemoryNudgeStateStore
from nudge_worker.worker import NudgeWorker


async def _async_main() -> None:
    parser = argparse.ArgumentParser(description="nudge-worker")
    parser.add_argument("--mode", choices=["worker", "job"], default="worker")
    parser.add_argument(
        "--job",
        choices=["morning-planning", "daily-summary", "end-of-day-reflection"],
        default="daily-summary",
    )
    args = parser.parse_args()

    settings = get_settings()
    configure_logging(settings.log_level)
    logger = logging.getLogger(__name__)

    vikunja_client = VikunjaClient(settings)
    ntfy_client = NtfyClient(settings)
    openai_client = OpenAIClient(settings) if settings.has_openai_credentials else None
    coach = CoachingComposer(openai_client=openai_client)
    state_store = InMemoryNudgeStateStore()
    agent_client = AgentServiceClient(settings) if settings.agent_service_base_url else None

    worker = NudgeWorker(
        settings=settings,
        vikunja_client=vikunja_client,
        ntfy_client=ntfy_client,
        state_store=state_store,
        coach=coach,
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
        if openai_client is not None:
            await openai_client.close()
        if agent_client is not None:
            await agent_client.close()


def main() -> None:
    asyncio.run(_async_main())


if __name__ == "__main__":
    main()
