# Callback Shadow Test Calls

Use these after importing and activating 06-telegram-callback-shadow.

## 1) First callback event

```bash
curl -sS -X POST "https://n8n.myrobertson.com/webhook/parallel/telegram/callback" \
  -H "Content-Type: application/json" \
  -d '{
    "callback_id": "cb-001",
    "session_id": "sess-abc",
    "action": "nudge_done",
    "callback_data": "done:42",
    "message_text": "Mark task done"
  }'
```

Expected response shape:

```json
{
  "ok": true,
  "handled": true,
  "duplicate": false,
  "mode": "shadow"
}
```

## 2) Duplicate callback event

Run the exact same command again.

Expected response when claim service is configured and returns claimed=false:

```json
{
  "ok": true,
  "handled": true,
  "duplicate": true,
  "mode": "shadow"
}
```

## Optional env hooks

- N8N_CALLBACK_CLAIM_URL
- N8N_SESSION_UPSERT_URL
- N8N_PARITY_EVENT_URL

Without claim hook configured, workflow defaults to duplicate=false and state_source=no-claim-service.
