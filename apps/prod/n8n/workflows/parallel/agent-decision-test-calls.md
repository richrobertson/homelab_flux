# Agent Decision Shadow Test Calls

Use these after importing and activating 09-agent-decision-shadow and 07-telegram-action-shadow.

## 1) Expected skip when parity fails

```bash
curl -sS -X POST "https://n8n.myrobertson.com/webhook/parallel/agent/decision" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-abc",
    "mode": "shadow",
    "parity_status": "fail",
    "action": "send_message",
    "chat_id": "123456789",
    "text": "Should not send"
  }'
```

## 2) Trigger path when parity passes and env gate is true

Prereq:

- N8N_AGENT_DECISION_ALLOW_ACTION=true
- N8N_TELEGRAM_SHADOW_ALLOW_SEND=true

```bash
curl -sS -X POST "https://n8n.myrobertson.com/webhook/parallel/agent/decision" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "sess-abc",
    "mode": "shadow",
    "parity_status": "pass",
    "action": "send_message",
    "chat_id": "123456789",
    "text": "Parity pass action test"
  }'
```
