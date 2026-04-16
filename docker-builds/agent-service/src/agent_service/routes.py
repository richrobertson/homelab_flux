from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException, Response, status

from agent_service.config import Settings
from agent_service.models import ChatRequest, ChatResponse, HealthResponse, TelegramUpdate

logger = logging.getLogger(__name__)


def build_router(settings: Settings, orchestrator: Any) -> APIRouter:
    router = APIRouter()

    @router.get("/healthz", response_model=HealthResponse)
    async def healthz() -> HealthResponse:
        return HealthResponse(status="ok", service=settings.app_name, now=datetime.now(timezone.utc))

    @router.get("/readyz")
    async def readyz(response: Response) -> dict[str, Any]:
        checks = {
            "openai_api_key": bool(settings.openai_api_key),
            "vikunja_base_url": bool(settings.vikunja_base_url),
            "vikunja_api_token": bool(settings.vikunja_api_token),
        }
        dependency_status = all(checks.values())
        response.status_code = status.HTTP_200_OK
        return {
            "ready": True,
            "checks": checks,
            "dependenciesConfigured": dependency_status,
        }

    @router.post("/chat", response_model=ChatResponse)
    async def chat(payload: ChatRequest) -> ChatResponse:
        text, tool_calls = await orchestrator.handle_chat(
            session_id=payload.session_id,
            user_message=payload.message,
        )
        return ChatResponse(session_id=payload.session_id, response=text, tool_calls=tool_calls)

    @router.post("/webhooks/telegram")
    async def telegram_webhook(
        update: TelegramUpdate,
        x_telegram_bot_api_secret_token: str | None = Header(default=None),
    ) -> dict[str, Any]:
        if settings.telegram_webhook_secret:
            if x_telegram_bot_api_secret_token != settings.telegram_webhook_secret:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook secret")

        if not update.message or not update.message.text:
            return {"ok": True, "ignored": True, "reason": "No message text"}

        chat_id = update.message.chat.id
        session_id = f"telegram:{chat_id}"
        reply, _ = await orchestrator.handle_chat(session_id=session_id, user_message=update.message.text)

        if not settings.telegram_bot_token:
            logger.warning("telegram_bot_token_missing")
            return {"ok": True, "delivered": False, "reply": reply}

        url = f"https://api.telegram.org/bot{settings.telegram_bot_token}/sendMessage"
        async with httpx.AsyncClient(timeout=15) as client:
            telegram_response = await client.post(url, json={"chat_id": chat_id, "text": reply})
            telegram_response.raise_for_status()

        return {"ok": True, "delivered": True}

    return router
