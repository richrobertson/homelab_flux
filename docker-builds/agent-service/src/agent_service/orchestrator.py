from __future__ import annotations

import json
import logging
from typing import Any

from agent_service.behavior import assess_behavior, build_behavior_system_hint
from agent_service.config import Settings
from agent_service.models import ToolCallRecord
from agent_service.prompts import DEFAULT_SYSTEM_PROMPT, build_system_prompt_with_context
from agent_service.session_store import InMemorySessionStore
from agent_service.tools import TOOL_SCHEMAS, ToolExecutor

logger = logging.getLogger(__name__)


class AgentOrchestrator:
    def __init__(
        self,
        settings: Settings,
        openai_client: Any,
        tool_executor: ToolExecutor,
        session_store: InMemorySessionStore,
    ) -> None:
        self._settings = settings
        self._openai = openai_client
        self._tools = tool_executor
        self._store = session_store

    async def handle_chat(
        self,
        session_id: str,
        user_message: str,
        attachments_context: str | None = None,
        attachments: list[Any] | None = None,
    ) -> tuple[str, list[ToolCallRecord]]:
        history = await self._store.get_messages(session_id)
        base_prompt = self._settings.agent_system_prompt or DEFAULT_SYSTEM_PROMPT
        system_prompt = build_system_prompt_with_context(base_prompt)
        behavior = assess_behavior(user_message)

        rendered_user_message = user_message
        stored_user_message = user_message
        if attachments:
            attachment_names = ", ".join(
                str(getattr(attachment, "filename", "attachment")) for attachment in attachments if attachment is not None
            )
            if attachment_names:
                stored_user_message = f"{user_message}\n\n[Attached files: {attachment_names}]".strip()
        if attachments_context:
            rendered_user_message = (
                f"{user_message}\n\n"
                "Attached file context:\n"
                "Use this extracted file content when answering.\n\n"
                f"{attachments_context}"
            )

        messages: list[dict[str, Any]] = [
            {"role": "system", "content": system_prompt},
        ]

        if behavior is not None:
            messages.append({"role": "system", "content": build_behavior_system_hint(behavior)})

        messages.extend([
            *history,
            {"role": "user", "content": rendered_user_message},
        ])

        tool_records: list[ToolCallRecord] = []
        final_response = ""

        if attachments:
            self._tools.set_session_attachments(session_id, attachments)

        try:
            for iteration in range(self._settings.tool_max_iterations):
                assistant_message = await self._openai.create_response(messages=messages, tools=TOOL_SCHEMAS)
                messages.append(assistant_message)

                tool_calls = assistant_message.get("tool_calls") or []
                if not tool_calls:
                    final_response = assistant_message.get("content") or "I can help with that."
                    break

                logger.info("model_requested_tools", extra={"count": len(tool_calls), "iteration": iteration})

                for call in tool_calls:
                    name = call["function"]["name"]
                    try:
                        arguments = json.loads(call["function"].get("arguments") or "{}")
                    except json.JSONDecodeError:
                        arguments = {}

                    result = await self._tools.execute(name, arguments, session_id=session_id)
                    tool_records.append(ToolCallRecord(name=name, arguments=arguments, result=result))

                    messages.append(
                        {
                            "role": "tool",
                            "tool_call_id": call["id"],
                            "name": name,
                            "content": json.dumps(result),
                        }
                    )
        finally:
            self._tools.clear_session_attachments(session_id)

        if not final_response:
            final_response = "I hit a tool-calling limit. Please try again with a more specific request."

        await self._store.append_messages(
            session_id,
            [
                {"role": "user", "content": stored_user_message},
                {"role": "assistant", "content": final_response},
            ],
        )

        return final_response, tool_records

    async def append_exchange(self, session_id: str, user_message: str, assistant_message: str) -> None:
        await self._store.append_messages(
            session_id,
            [
                {"role": "user", "content": user_message},
                {"role": "assistant", "content": assistant_message},
            ],
        )
