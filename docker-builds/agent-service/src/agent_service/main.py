from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from agent_service.clients.openai_client import OpenAIChatClient
from agent_service.clients.vikunja_client import VikunjaClient
from agent_service.config import get_settings
from agent_service.logging_config import configure_logging
from agent_service.orchestrator import AgentOrchestrator
from agent_service.routes import build_router
from agent_service.session_store import InMemorySessionStore
from agent_service.storage.postgres_store import PostgresStore
from agent_service.storage.redis_store import RedisSessionStore
from agent_service.tools import ToolExecutor

settings = get_settings()
configure_logging(settings.log_level)
logger = logging.getLogger(__name__)

openai_client = OpenAIChatClient(settings)
vikunja_client = VikunjaClient(settings)
postgres_store = PostgresStore(settings.effective_postgres_dsn)

if settings.redis_url:
    session_store = RedisSessionStore(
        redis_url=settings.redis_url,
        ttl_seconds=settings.session_ttl_seconds,
        max_messages=settings.session_max_messages,
        key_prefix=settings.redis_key_prefix,
    )
else:
    session_store = InMemorySessionStore(
        ttl_seconds=settings.session_ttl_seconds,
        max_messages=settings.session_max_messages,
    )

tool_executor = ToolExecutor(vikunja_client)
orchestrator = AgentOrchestrator(
    settings=settings,
    openai_client=openai_client,
    tool_executor=tool_executor,
    session_store=session_store,
)


@asynccontextmanager
async def lifespan(_: FastAPI):
    logger.info("agent_service_starting")
    await postgres_store.initialize()
    yield
    await openai_client.close()
    await vikunja_client.close()
    if hasattr(session_store, "close"):
        await session_store.close()
    await postgres_store.close()
    logger.info("agent_service_stopped")


app = FastAPI(title="agent-service", version="0.2.0", lifespan=lifespan)
app.include_router(
    build_router(
        settings=settings,
        orchestrator=orchestrator,
        postgres_store=postgres_store,
        redis_store=session_store if isinstance(session_store, RedisSessionStore) else None,
    )
)
