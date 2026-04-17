# Parity Log Test Calls

Use these examples after importing `05-parity-log-shadow` and activating it in n8n.

## 1) Basic parity event

```bash
curl -sS -X POST "https://n8n.myrobertson.com/webhook/parallel/parity/log" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "n8n-shadow",
    "session_id": "sess-123",
    "intent": "suggest_next_task",
    "mode": "shadow",
    "status": "ok",
    "candidate_task_ids": [101, 109, 125],
    "selected_task_id": 109,
    "action_preview": "suggest: Follow up with storage migration",
    "notes": "shadow decision only"
  }'
```

Expected response shape:

```json
{
  "ok": true,
  "logged": true,
  "sink": false,
  "checksum": "...",
  "recorded_at": "..."
}
```

## 2) Task-control-plane comparison event

```bash
curl -sS -X POST "https://n8n.myrobertson.com/webhook/parallel/parity/log" \
  -H "Content-Type: application/json" \
  -d '{
    "source": "task-control-plane",
    "session_id": "sess-123",
    "intent": "suggest_next_task",
    "mode": "prod",
    "status": "ok",
    "candidate_task_ids": [101, 109, 125],
    "selected_task_id": 101,
    "action_preview": "suggest: Patch gateway route",
    "notes": "prod decision"
  }'
```

## Optional external sink

Set `N8N_PARITY_LOG_SINK_URL` in n8n to forward normalized parity events to your own collector.
