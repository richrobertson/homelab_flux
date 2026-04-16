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
from agent_service.tools import ToolExecutor

settings = get_settings()
configure_logging(settings.log_level)
logger = logging.getLogger(__name__)

openai_client = OpenAIChatClient(settings)
vikunja_client = VikunjaClient(settings)
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
    yield
    await openai_client.close()
    await vikunja_client.close()
    logger.info("agent_service_stopped")


app = FastAPI(title="agent-service", version="0.1.0", lifespan=lifespan)
app.include_router(build_router(settings=settings, orchestrator=orchestrator))
