# Parallel Workflow Activation Checklist

This checklist keeps rollout in shadow mode and avoids accidental cutover.

## 1) Import workflows in order

1. 00-env-contract
2. 01-telegram-intake-shadow
3. 02-task-router-shadow
4. 03-nudge-scan-shadow
5. 04-scheduled-jobs-shadow
6. 05-parity-log-shadow
7. 06-telegram-callback-shadow
8. 07-telegram-action-shadow
9. 08-callback-state-shadow
10. 09-agent-decision-shadow

## 2) Keep safe defaults

- N8N_PARALLEL_ENABLE_WRITES=false
- N8N_TELEGRAM_SHADOW_ALLOW_SEND=false
- N8N_AGENT_DECISION_ALLOW_ACTION=false

## 3) Activate baseline observability first

- 05-parity-log-shadow
- 08-callback-state-shadow

## 4) Activate shadow intake and routing

- 01-telegram-intake-shadow
- 02-task-router-shadow
- 03-nudge-scan-shadow
- 04-scheduled-jobs-shadow
- 06-telegram-callback-shadow

## 5) Activate gated action layers last

- 07-telegram-action-shadow
- 09-agent-decision-shadow

## 6) Validate with test calls

- parity-test-calls.md
- callback-test-calls.md
- telegram-action-test-calls.md
- agent-decision-test-calls.md

## 7) Optional controlled execution tests

Enable only for short tests, then disable:

- N8N_PARALLEL_ENABLE_WRITES=true
- N8N_TELEGRAM_SHADOW_ALLOW_SEND=true
- N8N_AGENT_DECISION_ALLOW_ACTION=true

After tests, set all three back to false.
