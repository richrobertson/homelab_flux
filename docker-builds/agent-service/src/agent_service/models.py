from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    session_id: str = Field(..., min_length=1)
    message: str = Field(..., min_length=1)


class ToolCallRecord(BaseModel):
    name: str
    arguments: dict[str, Any]
    result: dict[str, Any]


class ChatResponse(BaseModel):
    session_id: str
    response: str
    tool_calls: list[ToolCallRecord] = Field(default_factory=list)


class TelegramChat(BaseModel):
    id: int
    type: str


class TelegramUser(BaseModel):
    id: int
    is_bot: Optional[bool] = False
    first_name: Optional[str] = None
    username: Optional[str] = None


class TelegramMessage(BaseModel):
    message_id: int
    date: int
    chat: TelegramChat
    text: Optional[str] = None
    from_: Optional[TelegramUser] = Field(default=None, alias="from")


class TelegramUpdate(BaseModel):
    update_id: int
    message: Optional[TelegramMessage] = None


class HealthResponse(BaseModel):
    status: str
    service: str
    now: datetime
