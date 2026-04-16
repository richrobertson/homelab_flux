from typing import Any

from openai import AsyncOpenAI

from agent_service.config import Settings


class OpenAIChatClient:
    def __init__(self, settings: Settings) -> None:
        self._client = AsyncOpenAI(
            api_key=settings.openai_api_key,
            base_url=settings.openai_base_url,
            timeout=settings.openai_timeout_seconds,
        )
        self._model = settings.openai_model

    async def create_response(
        self,
        messages: list[dict[str, Any]],
        tools: list[dict[str, Any]],
    ) -> dict[str, Any]:
        completion = await self._client.chat.completions.create(
            model=self._model,
            messages=messages,
            tools=tools,
            tool_choice="auto",
            temperature=0.2,
        )

        choice = completion.choices[0].message
        response_message: dict[str, Any] = {
            "role": "assistant",
            "content": choice.content or "",
        }

        if choice.tool_calls:
            response_message["tool_calls"] = [
                {
                    "id": call.id,
                    "type": "function",
                    "function": {
                        "name": call.function.name,
                        "arguments": call.function.arguments or "{}",
                    },
                }
                for call in choice.tool_calls
            ]

        return response_message

    async def close(self) -> None:
        await self._client.close()
