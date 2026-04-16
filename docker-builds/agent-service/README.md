# Agent Service (Phase 3)

Python FastAPI service that provides chat + tool-calling orchestration for task-control-plane.

## Features

- POST /chat for direct chat integration
- POST /webhooks/telegram for Telegram webhook traffic
- GET /healthz and GET /readyz
- OpenAI tool calling
- Vikunja task adapter
- In-memory session context (Redis-ready seam)

## Build

```bash
cd docker-builds/agent-service
docker build -t ghcr.io/<owner>/agent-service:0.1.0 .
```

## Run local

```bash
cd docker-builds/agent-service
cp .env.example .env
export $(grep -v '^#' .env | xargs)
uvicorn agent_service.main:app --host 0.0.0.0 --port 8080 --app-dir src
```

## Example chat request

```bash
curl -sS http://localhost:8080/chat \
  -H 'content-type: application/json' \
  -d '{"session_id":"local-1","message":"What should I work on next?"}'
```
