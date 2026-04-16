from __future__ import annotations

import logging
import time
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException, Response, status
from fastapi.responses import PlainTextResponse

from agent_service.behavior import assess_behavior, extract_task_id
from agent_service.config import Settings
from agent_service.metrics import (
    chat_request_latency_seconds,
    postgres_event_writes_total,
    redis_state_reads_total,
    redis_state_writes_total,
    render_metrics,
    telegram_messages_received_total,
    telegram_messages_sent_total,
)
from agent_service.models import ChatRequest, ChatResponse, HealthResponse, TelegramUpdate

logger = logging.getLogger(__name__)


async def _safe_send_telegram(bot_token: str, chat_id: int, text: str) -> None:
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    async with httpx.AsyncClient(timeout=15) as client:
        telegram_response = await client.post(url, json={"chat_id": chat_id, "text": text})
        telegram_response.raise_for_status()


def build_router(settings: Settings, orchestrator: Any, postgres_store: Any | None = None, redis_store: Any | None = None) -> APIRouter:
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
            "postgres_dsn": bool(settings.effective_postgres_dsn),
            "redis_url": bool(settings.redis_url),
        }
        dependency_status = all(checks.values())
        response.status_code = status.HTTP_200_OK
        return {
            "ready": True,
            "checks": checks,
            "dependenciesConfigured": dependency_status,
        }

    @router.get("/metrics")
    async def metrics() -> PlainTextResponse:
        return PlainTextResponse(content=render_metrics().decode("utf-8"), media_type="text/plain; version=0.0.4")

    @router.post("/chat", response_model=ChatResponse)
    async def chat(payload: ChatRequest) -> ChatResponse:
        started = time.perf_counter()
        text, tool_calls = await orchestrator.handle_chat(
            session_id=payload.session_id,
            user_message=payload.message,
        )
        chat_request_latency_seconds.observe(time.perf_counter() - started)
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

        telegram_messages_received_total.inc()
        message_text = update.message.text.strip()
        chat_id = update.message.chat.id
        user_id = str(update.message.from_.id) if update.message.from_ else None
        session_id = f"telegram:{chat_id}"

        behavior = assess_behavior(message_text)
        task_id = extract_task_id(message_text)

        if postgres_store is not None:
            await postgres_store.record_chat_seen(
                chat_id=chat_id,
                user_id=user_id,
                username=update.message.from_.username if update.message.from_ else None,
                first_name=update.message.from_.first_name if update.message.from_ else None,
            )
            postgres_event_writes_total.inc()

        if behavior and postgres_store is not None:
            await postgres_store.record_user_signal(
                signal_type=behavior.category,
                raw_text=message_text,
                normalized_action=behavior.coaching_instruction,
                related_task_id=task_id,
                user_id=user_id,
            )
            postgres_event_writes_total.inc()

        if redis_store is not None:
            redis_state_writes_total.inc()
            await redis_store.update_telegram_session(
                chat_id=chat_id,
                message_text=message_text,
                signal_type=behavior.category if behavior else None,
                user_id=user_id,
            )
            if user_id:
                await redis_store.set_user_state(
                    user_id=user_id,
                    current_energy="low" if behavior and behavior.category in {"overwhelmed", "low_energy"} else "normal",
                    last_signal=behavior.category if behavior else None,
                    focus_task_id=task_id,
                )

        upper = message_text.upper()
        if upper.startswith("START") and task_id and postgres_store is not None:
            await postgres_store.start_task_execution(task_id)
            await postgres_store.record_nudge_response(task_id=task_id, nudge_type="start", response_type="started", channel="telegram")
            postgres_event_writes_total.inc(2)
        elif upper.startswith("SNOOZE") and task_id and postgres_store is not None:
            await postgres_store.record_nudge_response(task_id=task_id, nudge_type="reminder", response_type="snoozed", channel="telegram")
            postgres_event_writes_total.inc()
        elif upper.startswith("BLOCKED") and task_id and postgres_store is not None:
            await postgres_store.record_nudge_response(task_id=task_id, nudge_type="escalation", response_type="blocked", channel="telegram")
            postgres_event_writes_total.inc()
        elif upper.startswith("BREAK IT DOWN") and task_id and postgres_store is not None:
            await postgres_store.record_nudge_response(task_id=task_id, nudge_type="recovery", response_type="break_down", channel="telegram")
            postgres_event_writes_total.inc()

        reply, _ = await orchestrator.handle_chat(session_id=session_id, user_message=message_text)

        if not settings.telegram_bot_token:
            logger.warning("telegram_bot_token_missing")
            return {"ok": True, "delivered": False, "reply": reply}

        await _safe_send_telegram(settings.telegram_bot_token, chat_id, reply)
        telegram_messages_sent_total.inc()
        return {"ok": True, "delivered": True}

    @router.post("/internal/telegram/send")
    async def internal_telegram_send(payload: dict[str, Any]) -> dict[str, Any]:
        if not settings.telegram_bot_token:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Telegram token not configured")

        text = str(payload.get("text") or "").strip()
        if not text:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="text is required")

        requested_chat_id = payload.get("chat_id")
        chat_ids: list[int] = []
        if requested_chat_id is not None:
            chat_ids.append(int(requested_chat_id))
        elif postgres_store is not None:
            chat_ids.extend(await postgres_store.list_recent_chat_ids())
            redis_state_reads_total.inc()

        if not chat_ids and settings.telegram_primary_chat_id:
            chat_ids.append(int(settings.telegram_primary_chat_id))

        if not chat_ids:
            return {"ok": True, "sent": 0, "reason": "no_known_chat"}

        sent = 0
        for chat_id in dict.fromkeys(chat_ids):
            await _safe_send_telegram(settings.telegram_bot_token, chat_id, text)
            sent += 1
            telegram_messages_sent_total.inc()

        return {"ok": True, "sent": sent}

    return router
