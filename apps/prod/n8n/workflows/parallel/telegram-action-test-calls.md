# Telegram Action Shadow Test Calls

Use these after importing and activating 07-telegram-action-shadow.

## 1) Expected skip in default shadow mode

```bash
curl -sS -X POST "https://n8n.myrobertson.com/webhook/parallel/telegram/action" \
  -H "Content-Type: application/json" \
  -d '{
    "mode": "shadow",
    "parity_status": "pass",
    "session_id": "sess-abc",
    "chat_id": "123456789",
    "text": "Shadow ping",
    "action": "send_shadow_ping"
  }'
```

Expected response shape:

```json
{
  "ok": true,
  "executed": false,
  "sent": false,
  "reason": "gated by parity/env/mode"
}
```

## 2) Execute path (only when explicitly enabled)

Prereqs:

- N8N_TELEGRAM_SHADOW_ALLOW_SEND=true
- TELEGRAM_BOT_TOKEN set

```bash
curl -sS -X POST "https://n8n.myrobertson.com/webhook/parallel/telegram/action" \
  -H "Content-Type: application/json" \
  -d '{
    "mode": "execute",
    "parity_status": "pass",
    "session_id": "sess-abc",
    "chat_id": "123456789",
    "text": "Execute-path test",
    "action": "send_execute_test"
  }'
```

Expected response shape:

```json
{
  "ok": true,
  "executed": true,
  "sent": true
}
```
