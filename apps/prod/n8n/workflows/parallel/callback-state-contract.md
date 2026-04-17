# Callback State Contract

This contract supports idempotent Telegram callback handling in shadow mode.

## Required callback payload into workflow

- callback_id
- session_id (recommended)
- action
- callback_data
- message_text

## State hooks

- N8N_CALLBACK_CLAIM_URL
- N8N_SESSION_UPSERT_URL

Default values now point to internal workflow `08-callback-state-shadow`:

- `https://n8n.myrobertson.com/webhook/parallel/state/callback/claim`
- `https://n8n.myrobertson.com/webhook/parallel/state/session/upsert`

When configured (internal or external):

- claim endpoint receives:
  - callback_id
  - session_id
  - ttl_seconds
- claim endpoint should return:
  - claimed (boolean)

- session upsert endpoint receives:
  - session_id
  - last_callback_id
  - last_action
  - updated_at

## Suggested Postgres schema

```sql
create table if not exists n8n_callback_claims (
  callback_id text primary key,
  session_id text,
  claimed_at timestamptz not null default now(),
  expires_at timestamptz not null
);

create table if not exists n8n_session_context (
  session_id text primary key,
  last_callback_id text,
  last_action text,
  updated_at timestamptz not null default now()
);
```

## Suggested claim query semantics

Single-statement claim using upsert guard:

```sql
insert into n8n_callback_claims (callback_id, session_id, expires_at)
values ($1, $2, now() + interval '1 hour')
on conflict (callback_id) do nothing
returning callback_id;
```

- If row returned => claimed=true
- If no row returned => claimed=false (duplicate)

## Safety

- Workflow remains inactive by default.
- If hooks are unset or unreachable, callback workflow falls back to claimed=true with parity note state_source=no-claim-service.
- No production reply/action side effects are performed in this workflow.

## Durability note

`08-callback-state-shadow` currently uses n8n workflow static data.

- Pros: no external dependency, fast shadow-mode bring-up
- Tradeoff: state is not intended as durable long-term storage across all restart/scale scenarios

For long-lived production-grade idempotency, replace with Postgres or n8n Data Store backed persistence.
