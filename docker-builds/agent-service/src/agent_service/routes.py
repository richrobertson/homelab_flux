from __future__ import annotations

import logging
import time
import base64
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter, File, Form, Header, HTTPException, Response, UploadFile, status
from fastapi.responses import PlainTextResponse

from agent_service.behavior import assess_behavior, extract_task_id
from agent_service.config import Settings
from agent_service.file_ingest import build_attachments_context
from agent_service.metrics import (
    chat_request_latency_seconds,
    postgres_event_writes_total,
    redis_state_reads_total,
    redis_state_writes_total,
    render_metrics,
    telegram_messages_received_total,
    telegram_messages_sent_total,
)
from agent_service.models import ChatAttachment, ChatRequest, ChatResponse, HealthResponse, TelegramUpdate
from agent_service.telegram_ux import (
    build_breakdown_message,
    build_callback_data,
    build_task_keyboard,
    build_task_send_payload,
    format_callback_confirmation,
    parse_callback_data,
)

logger = logging.getLogger(__name__)

TELEGRAM_TEXT_LIMIT = 4000


async def _safe_send_telegram(
    bot_token: str,
    chat_id: int,
    text: str,
    reply_markup: dict[str, Any] | None = None,
) -> dict[str, Any]:
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    payload: dict[str, Any] = {"chat_id": chat_id, "text": text}
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    async with httpx.AsyncClient(timeout=15) as client:
        telegram_response = await client.post(url, json=payload)
        telegram_response.raise_for_status()
        return telegram_response.json()

async def _download_telegram_document(bot_token: str, document: Any) -> ChatAttachment:
    meta_url = f"https://api.telegram.org/bot{bot_token}/getFile"
    async with httpx.AsyncClient(timeout=30) as client:
        meta_response = await client.get(meta_url, params={"file_id": document.file_id})
        meta_response.raise_for_status()
        payload = meta_response.json()
        file_path = ((payload or {}).get("result") or {}).get("file_path")
        if not file_path:
            raise ValueError("Telegram file path missing from getFile response")

        download_url = f"https://api.telegram.org/file/bot{bot_token}/{file_path}"
        file_response = await client.get(download_url)
        file_response.raise_for_status()

    return ChatAttachment(
        filename=document.file_name or file_path.rsplit("/", 1)[-1],
        content_base64=base64.b64encode(file_response.content).decode("ascii"),
        mime_type=document.mime_type,
    )


async def _safe_answer_callback(bot_token: str, callback_query_id: str, text: str) -> None:
    url = f"https://api.telegram.org/bot{bot_token}/answerCallbackQuery"
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(url, json={"callback_query_id": callback_query_id, "text": text[:180]})
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError:
            logger.warning(
                "telegram_answer_callback_failed",
                extra={
                    "callback_query_id": callback_query_id,
                    "status_code": response.status_code,
                    "response_body": response.text,
                },
            )


async def _safe_edit_telegram_message(
    bot_token: str,
    chat_id: int,
    message_id: int,
    text: str,
    reply_markup: dict[str, Any] | None = None,
) -> None:
    url = f"https://api.telegram.org/bot{bot_token}/editMessageText"
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "message_id": message_id,
        "text": text,
    }
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(url, json=payload)
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError:
            logger.warning(
                "telegram_edit_message_failed",
                extra={
                    "chat_id": chat_id,
                    "message_id": message_id,
                    "status_code": response.status_code,
                    "response_body": response.text,
                },
            )


def _telegram_safe_text(text: str) -> str:
    cleaned = (text or "").strip()
    if len(cleaned) <= TELEGRAM_TEXT_LIMIT:
        return cleaned
    return cleaned[: TELEGRAM_TEXT_LIMIT - 1] + "…"


def _infer_action_from_text(message_text: str) -> tuple[str, dict[str, int]] | None:
    normalized = message_text.strip().lower()
    if normalized in {"ok", "yes", "push it", "do it", "start"}:
        return ("start", {})
    if normalized in {"later", "snooze", "snooze 15"}:
        return ("snooze", {"minutes": 15})
    if normalized == "snooze 30":
        return ("snooze", {"minutes": 30})
    if normalized in {"blocked", "stuck", "overwhelmed"}:
        return ("blocked", {})
    if normalized in {"break it down", "break this down"}:
        return ("break_down", {})
    if normalized in {"done", "finished", "complete"}:
        return ("done", {})
    return None


def build_router(
    settings: Settings,
    orchestrator: Any,
    postgres_store: Any | None = None,
    redis_store: Any | None = None,
    vikunja_client: Any | None = None,
    tool_executor: Any | None = None,
) -> APIRouter:
    router = APIRouter()

    async def _track_task_context(
        *,
        chat_id: int,
        user_id: str | None,
        task_id: int | None,
        task_title: str | None = None,
        action: str | None = None,
        message_type: str | None = None,
        message_id: int | None = None,
        clear_active_task: bool = False,
        set_active_task: bool = False,
    ) -> None:
        if redis_store is None or task_id is None:
            return
        await redis_store.update_telegram_context(
            chat_id,
            user_id=user_id,
            active_task_id=task_id if set_active_task else None,
            last_task_id=task_id,
            last_action=action,
            message_type=message_type,
            task_title=task_title,
            message_id=message_id,
            clear_active_task=clear_active_task,
        )

    async def _send_task_prompt(
        *,
        chat_id: int,
        user_id: str | None,
        task_id: int,
        task_title: str,
        message_type: str,
        body: str | None = None,
        duration_minutes: int | None = None,
    ) -> dict[str, Any]:
        payload = build_task_send_payload(
            task_id=task_id,
            task_title=task_title,
            message_type=message_type,
            body=body,
            duration_minutes=duration_minutes,
        )
        sent = await _safe_send_telegram(
            settings.telegram_bot_token or "",
            chat_id,
            _telegram_safe_text(str(payload["text"])),
            reply_markup=payload["reply_markup"],
        )
        message = sent.get("result") or {}
        message_id = message.get("message_id")
        await _track_task_context(
            chat_id=chat_id,
            user_id=user_id,
            task_id=task_id,
            task_title=task_title,
            action=f"sent_{message_type}",
            message_type=message_type,
            message_id=int(message_id) if isinstance(message_id, int) else None,
            set_active_task=message_type in {"check_in", "completion_check"},
        )
        return sent

    async def _apply_task_action(
        *,
        action: str,
        task_id: int,
        chat_id: int,
        user_id: str | None,
        minutes: int | None = None,
    ) -> dict[str, Any]:
        task_title = f"Task #{task_id}"
        if vikunja_client is not None:
            try:
                task = await vikunja_client.get_task(task_id)
                task_title = str(task.get("title") or task_title)
            except Exception as exc:  # noqa: BLE001
                logger.warning("telegram_task_lookup_failed", extra={"task_id": task_id, "error": str(exc)})

        confirmation_title, confirmation_text = format_callback_confirmation(action, task_title, task_id, minutes=minutes)
        message_type = "check_in"
        follow_up_text = confirmation_text
        reply_markup: dict[str, Any] | None = None

        if action == "start":
            if postgres_store is not None:
                await postgres_store.start_task_execution(task_id)
                await postgres_store.record_nudge_response(
                    task_id=task_id,
                    nudge_type="start",
                    response_type="started",
                    channel="telegram",
                    metadata={"source": "callback"},
                )
                postgres_event_writes_total.inc(2)
            await _track_task_context(
                chat_id=chat_id,
                user_id=user_id,
                task_id=task_id,
                task_title=task_title,
                action="start",
                message_type="check_in",
                set_active_task=True,
            )
            reply_markup = build_task_keyboard("check_in", task_id)
        elif action == "snooze":
            if redis_store is not None:
                await redis_store.set_manual_snooze(task_id, minutes or 15)
                redis_state_writes_total.inc()
            if postgres_store is not None:
                await postgres_store.record_nudge_response(
                    task_id=task_id,
                    nudge_type="reminder",
                    response_type=f"snoozed_{minutes or 15}",
                    channel="telegram",
                    metadata={"minutes": minutes or 15, "source": "callback"},
                )

            if update.message.document is not None and settings.telegram_bot_token:
                try:
                    attachments.append(await _download_telegram_document(settings.telegram_bot_token, update.message.document))
                except Exception as exc:  # noqa: BLE001
                    logger.warning("telegram_document_download_failed", extra={"chat_id": chat_id, "error": str(exc)})
                    if settings.telegram_bot_token:
                        await _safe_send_telegram(
                            settings.telegram_bot_token,
                            chat_id,
                            "I could not read that file from Telegram. Please try sending it again.",
                        )
                        telegram_messages_sent_total.inc()
                    return {"ok": True, "ignored": True, "reason": "telegram_document_download_failed"}

            if attachments and redis_store is not None:
                await redis_store.set_pending_telegram_attachments(
                    chat_id,
                    [attachment.model_dump() for attachment in attachments],
                )
                redis_state_writes_total.inc()

            if attachments and not message_text:
                if settings.telegram_bot_token:
                    await _safe_send_telegram(
                        settings.telegram_bot_token,
                        chat_id,
                        f"I received {attachments[0].filename}. Tell me what to do with it, or send a caption with the file.",
                    )
                    telegram_messages_sent_total.inc()
                return {"ok": True, "handled": True, "reason": "telegram_attachment_stored"}

            if not attachments and redis_store is not None:
                pending = await redis_store.get_pending_telegram_attachments(chat_id)
                if pending:
                    attachments = [ChatAttachment(**item) for item in pending]
                    redis_state_reads_total.inc()
                postgres_event_writes_total.inc()
            await _track_task_context(
                chat_id=chat_id,
                user_id=user_id,
                task_id=task_id,
                task_title=task_title,
                action=f"snooze_{minutes or 15}",
            )
            message_type = "nudge"
        elif action == "blocked":
            if postgres_store is not None:
                await postgres_store.record_nudge_response(
                    task_id=task_id,
                    nudge_type="escalation",
                    response_type="blocked",
                    channel="telegram",
                    metadata={"source": "callback"},
                )
                postgres_event_writes_total.inc()
            if redis_store is not None and user_id:
                await redis_store.set_user_state(
                    user_id=user_id,
                    current_energy="low",
                    last_signal="blocked",
                    focus_task_id=task_id,
                )
                redis_state_writes_total.inc()
            await _track_task_context(
                chat_id=chat_id,
                user_id=user_id,
                task_id=task_id,
                task_title=task_title,
                action="blocked",
                message_type="recovery",
                set_active_task=True,
            )
            message_type = "recovery"
            follow_up_text = f"Blocked: {task_title}\n\nWhat is blocking you?"
            reply_markup = build_task_keyboard("recovery", task_id)
        elif action == "break_down":
            steps: list[str] = []
            if tool_executor is not None:
                result = await tool_executor.execute("break_down_task", {"task_id": task_id, "title": task_title})
                steps = [str(step) for step in result.get("steps") or []]
            if postgres_store is not None:
                await postgres_store.record_nudge_response(
                    task_id=task_id,
                    nudge_type="recovery",
                    response_type="break_down",
                    channel="telegram",
                    metadata={"source": "callback"},
                )
                postgres_event_writes_total.inc()
            await _track_task_context(
                chat_id=chat_id,
                user_id=user_id,
                task_id=task_id,
                task_title=task_title,
                action="break_down",
                message_type="recovery",
            )
            message_type = "recovery"
            follow_up_text = build_breakdown_message(task_title, task_id, steps or ["Define the next 10-minute step."])
            reply_markup = build_task_keyboard("recovery", task_id)
        elif action == "done":
            if vikunja_client is not None:
                await vikunja_client.complete_task(task_id)
            if postgres_store is not None:
                await postgres_store.complete_task_execution(task_id)
                await postgres_store.record_nudge_response(
                    task_id=task_id,
                    nudge_type="completion_check",
                    response_type="done",
                    channel="telegram",
                    metadata={"source": "callback"},
                )
                postgres_event_writes_total.inc(2)
            await _track_task_context(
                chat_id=chat_id,
                user_id=user_id,
                task_id=task_id,
                task_title=task_title,
                action="done",
                clear_active_task=True,
            )
            message_type = "completion_check"
            follow_up_text = confirmation_text

        return {
            "task_title": task_title,
            "confirmation_title": confirmation_title,
            "confirmation_text": confirmation_text,
            "follow_up_text": follow_up_text,
            "message_type": message_type,
            "reply_markup": reply_markup,
        }

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
        attachments_context = build_attachments_context(payload.attachments)
        text, tool_calls = await orchestrator.handle_chat(
            session_id=payload.session_id,
            user_message=payload.message,
            attachments_context=attachments_context,
            attachments=payload.attachments,
        )
        chat_request_latency_seconds.observe(time.perf_counter() - started)
        return ChatResponse(session_id=payload.session_id, response=text, tool_calls=tool_calls)

    @router.post("/chat/multipart", response_model=ChatResponse)
    async def chat_multipart(
        session_id: str = Form(...),
        message: str = Form(...),
        files: list[UploadFile] = File(default_factory=list),
    ) -> ChatResponse:
        started = time.perf_counter()
        attachments: list[ChatAttachment] = []

        for upload in files:
            raw = await upload.read()
            encoded = base64.b64encode(raw).decode("ascii")
            attachments.append(
                ChatAttachment(
                    filename=upload.filename or "attachment.bin",
                    content_base64=encoded,
                    mime_type=upload.content_type,
                )
            )

        attachments_context = build_attachments_context(attachments)
        text, tool_calls = await orchestrator.handle_chat(
            session_id=session_id,
            user_message=message,
            attachments_context=attachments_context,
            attachments=attachments,
        )
        chat_request_latency_seconds.observe(time.perf_counter() - started)
        return ChatResponse(session_id=session_id, response=text, tool_calls=tool_calls)

    @router.put("/tasks/{task_id}/attachments")
    @router.put("/chat/tasks/{task_id}/attachments")
    async def upload_task_attachments(task_id: int, files: list[UploadFile] = File(...)) -> dict[str, Any]:
        if vikunja_client is None:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Vikunja client unavailable")

        uploaded: list[dict[str, Any]] = []
        for upload in files:
            content_bytes = await upload.read()
            result = await vikunja_client.upload_task_attachment(
                task_id=task_id,
                filename=upload.filename or "attachment.bin",
                content_bytes=content_bytes,
                mime_type=upload.content_type,
            )
            uploaded.extend(result)

        return {"ok": True, "task_id": task_id, "count": len(uploaded), "attachments": uploaded}

    @router.post("/webhooks/telegram")
    async def telegram_webhook(
        update: TelegramUpdate,
        x_telegram_bot_api_secret_token: str | None = Header(default=None),
    ) -> dict[str, Any]:
        if settings.telegram_webhook_secret:
            if x_telegram_bot_api_secret_token != settings.telegram_webhook_secret:
                raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid webhook secret")

        if update.callback_query is not None:
            callback = update.callback_query
            if not settings.telegram_bot_token:
                return {"ok": True, "ignored": True, "reason": "telegram_not_configured"}
            if not callback.data or callback.message is None:
                return {"ok": True, "ignored": True, "reason": "No callback payload"}

            if redis_store is not None:
                callback_claimed = await redis_store.claim_callback(callback.id)
                redis_state_writes_total.inc()
                if not callback_claimed:
                    await _safe_answer_callback(settings.telegram_bot_token, callback.id, "Already handled.")
                    return {"ok": True, "handled": True, "duplicate": True}

            payload = parse_callback_data(callback.data)
            action = payload.get("action")
            task_id_raw = payload.get("task_id")
            if not action or not task_id_raw:
                await _safe_answer_callback(settings.telegram_bot_token, callback.id, "Invalid action.")
                return {"ok": True, "ignored": True, "reason": "invalid_callback_payload"}

            task_id = int(task_id_raw)
            minutes = int(payload["minutes"]) if payload.get("minutes") else None
            chat_id = callback.message.chat.id
            user_id = str(callback.from_.id)
            result = await _apply_task_action(
                action=action,
                task_id=task_id,
                chat_id=chat_id,
                user_id=user_id,
                minutes=minutes,
            )

            await _safe_answer_callback(settings.telegram_bot_token, callback.id, result["confirmation_text"])

            try:
                await _safe_edit_telegram_message(
                    settings.telegram_bot_token,
                    chat_id,
                    callback.message.message_id,
                    _telegram_safe_text(result["confirmation_title"]),
                )
            except httpx.HTTPStatusError:
                logger.warning("telegram_edit_failed", extra={"chat_id": chat_id, "task_id": task_id, "action": action})

            if action in {"blocked", "break_down", "start"}:
                await _safe_send_telegram(
                    settings.telegram_bot_token,
                    chat_id,
                    _telegram_safe_text(result["follow_up_text"]),
                    reply_markup=result["reply_markup"],
                )
                telegram_messages_sent_total.inc()

            return {"ok": True, "handled": True, "action": action, "task_id": task_id}

        if not update.message or not (update.message.text or update.message.caption or update.message.document):
            return {"ok": True, "ignored": True, "reason": "No usable message content"}

        telegram_messages_received_total.inc()
        message_text = (update.message.text or update.message.caption or "").strip()
        chat_id = update.message.chat.id
        user_id = str(update.message.from_.id) if update.message.from_ else None
        session_id = f"telegram:{chat_id}"
        attachments: list[ChatAttachment] = []

        if update.message.document is not None and settings.telegram_bot_token:
            try:
                attachments.append(await _download_telegram_document(settings.telegram_bot_token, update.message.document))
            except Exception as exc:  # noqa: BLE001
                logger.warning("telegram_document_download_failed", extra={"chat_id": chat_id, "error": str(exc)})
                await _safe_send_telegram(
                    settings.telegram_bot_token,
                    chat_id,
                    "I could not read that file from Telegram. Please try sending it again.",
                )
                telegram_messages_sent_total.inc()
                return {"ok": True, "ignored": True, "reason": "telegram_document_download_failed"}

        if attachments and redis_store is not None:
            await redis_store.set_pending_telegram_attachments(
                chat_id,
                [attachment.model_dump() for attachment in attachments],
            )
            redis_state_writes_total.inc()

        if attachments and not message_text:
            if settings.telegram_bot_token:
                await _safe_send_telegram(
                    settings.telegram_bot_token,
                    chat_id,
                    f"I received {attachments[0].filename}. Tell me what to do with it, or send a caption with the file.",
                )
                telegram_messages_sent_total.inc()
            return {"ok": True, "handled": True, "reason": "telegram_attachment_stored"}

        if not attachments and redis_store is not None:
            pending = await redis_store.get_pending_telegram_attachments(chat_id)
            if pending:
                attachments = [ChatAttachment(**item) for item in pending]
                redis_state_reads_total.inc()

        behavior = assess_behavior(message_text)
        task_id = extract_task_id(message_text)
        if task_id is None and redis_store is not None:
            task_id = await redis_store.infer_task_id(chat_id, message_text)
            if task_id is not None:
                redis_state_reads_total.inc()

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
                message_text=message_text or (attachments[0].filename if attachments else "[attachment]"),
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
            await redis_store.update_telegram_context(
                chat_id,
                user_id=user_id,
                last_task_id=task_id,
                last_action="message",
            )

        inferred_action = _infer_action_from_text(message_text)
        if inferred_action is not None and task_id is not None:
            action, metadata = inferred_action
            result = await _apply_task_action(
                action=action,
                task_id=task_id,
                chat_id=chat_id,
                user_id=user_id,
                minutes=metadata.get("minutes"),
            )

            if not settings.telegram_bot_token:
                return {"ok": True, "handled": True, "reason": "telegram_not_configured"}

            await _safe_send_telegram(
                settings.telegram_bot_token,
                chat_id,
                _telegram_safe_text(result["follow_up_text"]),
                reply_markup=result["reply_markup"],
            )
            telegram_messages_sent_total.inc()
            return {"ok": True, "handled": True, "action": action, "task_id": task_id}

        attachments_context = build_attachments_context(attachments)
        reply, _ = await orchestrator.handle_chat(
            session_id=session_id,
            user_message=message_text,
            attachments_context=attachments_context,
            attachments=attachments,
        )

        if attachments and redis_store is not None:
            await redis_store.clear_pending_telegram_attachments(chat_id)
            redis_state_writes_total.inc()

        if not settings.telegram_bot_token:
            logger.warning("telegram_bot_token_missing")
            return {"ok": True, "delivered": False, "reply": reply}

        try:
            await _safe_send_telegram(settings.telegram_bot_token, chat_id, _telegram_safe_text(reply))
            telegram_messages_sent_total.inc()
            return {"ok": True, "delivered": True}
        except httpx.HTTPStatusError as exc:
            body = ""
            try:
                body = exc.response.text
            except Exception:
                body = "<unavailable>"
            logger.warning(
                "telegram_send_failed",
                extra={
                    "chat_id": chat_id,
                    "status_code": exc.response.status_code,
                    "response_body": body,
                },
            )
            return {"ok": True, "delivered": False, "reason": "send_failed"}

    @router.post("/internal/telegram/send")
    async def internal_telegram_send(payload: dict[str, Any]) -> dict[str, Any]:
        if not settings.telegram_bot_token:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Telegram token not configured")

        text = str(payload.get("text") or "").strip()
        task_id = payload.get("task_id")
        task_title = str(payload.get("task_title") or "").strip() or None
        message_type = str(payload.get("message_type") or "").strip() or None
        reply_markup = payload.get("reply_markup")
        duration_minutes_raw = payload.get("duration_minutes")
        duration_minutes = int(duration_minutes_raw) if duration_minutes_raw is not None else None
        if not text and not (task_id is not None and task_title and message_type):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="text is required")
        if task_id is not None and (task_title is None or message_type is None):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="task_title and message_type are required with task_id")

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
        sent_message_ids: list[int] = []
        for chat_id in dict.fromkeys(chat_ids):
            try:
                if task_id is not None and task_title is not None and message_type is not None:
                    telegram_response = await _send_task_prompt(
                        chat_id=chat_id,
                        user_id=None,
                        task_id=int(task_id),
                        task_title=task_title,
                        message_type=message_type,
                        body=text or None,
                        duration_minutes=duration_minutes,
                    )
                else:
                    telegram_response = await _safe_send_telegram(
                        settings.telegram_bot_token,
                        chat_id,
                        _telegram_safe_text(text),
                        reply_markup=reply_markup if isinstance(reply_markup, dict) else None,
                    )
                sent += 1
                telegram_messages_sent_total.inc()
                result = telegram_response.get("result") or {}
                if isinstance(result.get("message_id"), int):
                    sent_message_ids.append(int(result["message_id"]))
            except httpx.HTTPStatusError as exc:
                body = ""
                try:
                    body = exc.response.text
                except Exception:
                    body = "<unavailable>"
                logger.warning(
                    "internal_telegram_send_failed",
                    extra={
                        "chat_id": chat_id,
                        "status_code": exc.response.status_code,
                        "response_body": body,
                    },
                )

        return {"ok": True, "sent": sent, "message_ids": sent_message_ids}

    return router
