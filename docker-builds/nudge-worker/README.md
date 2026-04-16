# Nudge Worker

Phase 4 and 5 worker for proactive task coaching.

## Modes

- worker: polling loop that scans Vikunja and sends nudges
- job: one-shot summary or planning jobs

## Build

```bash
cd docker-builds/nudge-worker
docker build -t ghcr.io/<owner>/nudge-worker:0.1.0 .
```

## Local run

```bash
cd docker-builds/nudge-worker
cp .env.example .env
export $(grep -v '^#' .env | xargs)
PYTHONPATH=src python -m nudge_worker.main --mode worker
```

## One-shot job

```bash
PYTHONPATH=src python -m nudge_worker.main --mode job --job morning-planning
```
