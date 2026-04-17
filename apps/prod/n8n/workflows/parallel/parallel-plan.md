# Parallel n8n Workflow Pack (No Cutover)

This folder starts the n8n migration in shadow mode only.

## Import order

1. `00-env-contract.json`
2. `01-telegram-intake-shadow.json`
3. `02-task-router-shadow.json`
4. `03-nudge-scan-shadow.json`
5. `04-scheduled-jobs-shadow.json`
6. `05-parity-log-shadow.json`
7. `06-telegram-callback-shadow.json`
8. `07-telegram-action-shadow.json`
9. `08-callback-state-shadow.json`
10. `09-agent-decision-shadow.json`

## Safety guardrails

- All workflows are `active: false` by default.
- Webhook paths are prefixed with `parallel/` to avoid collisions.
- Task write-paths are hard-gated and only run when request body sets `mode=execute` and env var `N8N_PARALLEL_ENABLE_WRITES=true`.
- Nudge workflows currently classify only and do not send notifications.
- Router and nudge shadow flows emit parity events automatically (non-blocking, response-code ignored).

## Next implementation pass

- Swap `08-callback-state-shadow` function-node state to Postgres/Data Store for durable persistence.
- Add cutover checklist and staged activation order for selected workflows.

## Parity event endpoint

- Webhook path: `parallel/parity/log`
- Emit target URL override: `N8N_PARITY_EVENT_URL` (defaults to `https://n8n.myrobertson.com/webhook/parallel/parity/log`)
- Optional sink forwarding: set `N8N_PARITY_LOG_SINK_URL`
- Suggested payload fields:
  - `source` (for example `n8n-shadow` or `task-control-plane`)
  - `session_id`
  - `intent`
  - `mode`
  - `status`
  - `candidate_task_ids` (array)
  - `selected_task_id`
  - `action_preview`
  - `notes`

## Current execute coverage in `02-task-router-shadow`

- `create_task` (PUT `/projects/{project_id}/tasks`)
- `create_subtask` (create task + relation `subtask`)
- `update_task` (GET current task + POST merged payload)
- `delete_task` (DELETE `/tasks/{task_id}`)
- `attach_file_to_task` (PUT multipart `/tasks/{task_id}/attachments`)

All execute branches remain blocked by default unless both are true:

- Request body includes `mode=execute`
- Env var `N8N_PARALLEL_ENABLE_WRITES=true`

## Callback shadow coverage in `06-telegram-callback-shadow`

- Webhook path: `parallel/telegram/callback`
- Idempotency check via `N8N_CALLBACK_CLAIM_URL` (defaults to internal `08-callback-state-shadow` endpoint)
- Session context upsert via `N8N_SESSION_UPSERT_URL` (defaults to internal `08-callback-state-shadow` endpoint)
- Automatic parity emission with source `n8n-shadow-callback`
- Duplicate callbacks short-circuit with `duplicate=true`

## Telegram action shadow coverage in `07-telegram-action-shadow`

- Webhook path: `parallel/telegram/action`
- Send gate requires all of:
  - `mode=execute`
  - `parity_status=pass`
  - `N8N_TELEGRAM_SHADOW_ALLOW_SEND=true`
- Optional callback acknowledgment when `callback_id` is present
- Automatic parity emission for both `sent` and `skipped` outcomes

## Callback state shadow coverage in `08-callback-state-shadow`

- `parallel/state/callback/claim` callback claim endpoint
- `parallel/state/session/upsert` session context upsert endpoint
- Uses n8n workflow static data with TTL-based claim cleanup

## Agent decision shadow coverage in `09-agent-decision-shadow`

- Webhook path: `parallel/agent/decision`
- Triggers `07-telegram-action-shadow` only when:
  - `parity_status=pass`
  - `N8N_AGENT_DECISION_ALLOW_ACTION=true`
- Emits parity logs for `triggered` and `skipped` outcomes
