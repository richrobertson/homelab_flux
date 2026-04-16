#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


def _run(command: list[str], stdin_text: str | None = None) -> str:
    result = subprocess.run(
        command,
        input=stdin_text,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "Command failed: "
            + " ".join(command)
            + "\nSTDOUT:\n"
            + result.stdout
            + "\nSTDERR:\n"
            + result.stderr
        )
    return result.stdout.strip()


def _sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _normalize_text(raw: object) -> str:
    if isinstance(raw, str):
        return raw.strip()
    if isinstance(raw, list):
        parts: list[str] = []
        for item in raw:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                text_part = item.get("text")
                if isinstance(text_part, str):
                    parts.append(text_part)
        return "".join(parts).strip()
    return ""


def _parse_iso8601(ts: str) -> datetime:
    # Telegram export timestamps are typically like 2026-04-15T06:45:11
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


@dataclass
class BackfillRow:
    event_ts: datetime
    signal_type: str
    raw_text: str
    normalized_action: str
    user_id: str


def _classify_signal(message_text: str) -> tuple[str, str]:
    text = message_text.strip()
    upper = text.upper()
    if upper.startswith("START"):
        return "started", "START command (backfill)"
    if upper.startswith("SNOOZE"):
        return "snoozed", "SNOOZE command (backfill)"
    if upper.startswith("BLOCKED"):
        return "blocked", "BLOCKED command (backfill)"
    if upper.startswith("BREAK IT DOWN"):
        return "break_down", "BREAK IT DOWN command (backfill)"
    if upper == "/START":
        return "setup", "bot session start"
    if "WHAT SHOULD I WORK ON NEXT" in upper or "LIST THOSE TASKS" in upper:
        return "planning", "task prioritization request"
    if "INTERVIEW PERFORMANCE REPORT" in upper or "KEY AREAS FOR IMPROVEMENT" in upper:
        return "self_reflection", "shared interview performance reflection"
    if "DICTATE THE DAILY TASKS" in upper or "TAKE THE REINS" in upper:
        return "delegation", "requested stronger task direction"
    if "GO TO BED" in upper or "START TOMORROW" in upper:
        return "scheduling", "requested realistic scheduling"
    if "DATE" in upper or "DAY IT IS" in upper or "APRIL 15TH, 2026" in upper or "DATES ARE WRONG" in upper:
        return "date_correction", "corrected assistant date or schedule"
    if "DIRECT LINKS" in upper or "LINK TO THE FIRST TASK" in upper:
        return "task_navigation", "requested task links or navigation"
    if "THAT DOESN'T MAKE SENSE" in upper or "WHY NOT?" in upper:
        return "confusion", "pushed back on unclear assistant response"
    if upper in {"YES", "HELLO", "PING", "TRY AGAIN"}:
        return "check_in", "short chat acknowledgement"
    return "planning_context", "telegram historical chat backfill"


def _load_rows(export_file: Path, user_id: str) -> tuple[list[BackfillRow], str | None, datetime | None]:
    payload = json.loads(export_file.read_text(encoding="utf-8"))
    messages = payload.get("messages", [])
    rows: list[BackfillRow] = []
    first_name: str | None = None
    newest_ts: datetime | None = None
    normalized_user_id = user_id.removeprefix("user")
    accepted_from_ids = {user_id, normalized_user_id, f"user{normalized_user_id}"}

    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get("type") != "message":
            continue
        from_id = msg.get("from_id")
        if isinstance(from_id, str) and from_id not in accepted_from_ids:
            continue
        text = _normalize_text(msg.get("text"))
        if not text:
            continue
        date_raw = msg.get("date")
        if not isinstance(date_raw, str):
            continue
        try:
            event_ts = _parse_iso8601(date_raw)
        except ValueError:
            continue

        sender = msg.get("from")
        if isinstance(sender, str) and sender.strip() and first_name is None:
            first_name = sender.strip()[:128]

        signal_type, normalized_action = _classify_signal(text)
        rows.append(
            BackfillRow(
                event_ts=event_ts,
                signal_type=signal_type,
                raw_text=text,
                normalized_action=normalized_action,
                user_id=user_id,
            )
        )
        if newest_ts is None or event_ts > newest_ts:
            newest_ts = event_ts

    return rows, first_name, newest_ts


def _build_sql(rows: list[BackfillRow], chat_id: int, user_id: str, first_name: str | None, last_seen: datetime) -> str:
    values: list[str] = []
    for row in rows:
        values.append(
            "("
            + _sql_quote(row.event_ts.isoformat())
            + ","
            + _sql_quote(row.signal_type)
            + ",NULL,"
            + _sql_quote(row.raw_text)
            + ","
            + _sql_quote(row.normalized_action)
            + ","
            + _sql_quote(row.user_id)
            + ",'telegram')"
        )

    username = None
    if user_id.startswith("@"):
        username = user_id[1:]

    sql = ["BEGIN;"]
    if values:
        sql.append(
            "INSERT INTO user_signal (event_ts, signal_type, related_task_id, raw_text, normalized_action, user_id, channel) VALUES\n"
            + ",\n".join(values)
            + ";"
        )

    sql.append(
        "INSERT INTO telegram_chat_state (chat_id, last_seen_at, last_user_id, username, first_name) VALUES ("
        + str(chat_id)
        + ","
        + _sql_quote(last_seen.isoformat())
        + ","
        + _sql_quote(user_id)
        + ","
        + ("NULL" if username is None else _sql_quote(username))
        + ","
        + ("NULL" if first_name is None else _sql_quote(first_name))
        + ")\n"
        + "ON CONFLICT (chat_id) DO UPDATE SET\n"
        + "last_seen_at = GREATEST(telegram_chat_state.last_seen_at, EXCLUDED.last_seen_at),\n"
        + "last_user_id = COALESCE(EXCLUDED.last_user_id, telegram_chat_state.last_user_id),\n"
        + "username = COALESCE(EXCLUDED.username, telegram_chat_state.username),\n"
        + "first_name = COALESCE(EXCLUDED.first_name, telegram_chat_state.first_name);"
    )
    sql.append("COMMIT;")
    return "\n".join(sql)


def main() -> int:
    parser = argparse.ArgumentParser(description="Backfill Telegram export into task-control-plane Postgres tables")
    parser.add_argument("--export-file", required=True, help="Path to Telegram Desktop export JSON")
    parser.add_argument("--chat-id", required=True, type=int, help="Telegram chat_id to associate with backfilled messages")
    parser.add_argument("--user-id", required=True, help="User identifier stored in user_signal.last_user_id")
    parser.add_argument("--namespace", default="default")
    parser.add_argument("--cluster-name", default="task-control-plane-cnpg")
    parser.add_argument("--secret-name", default="task-control-plane-cnpg-app")
    parser.add_argument("--dry-run", action="store_true", help="Print summary only; do not write to DB")
    args = parser.parse_args()

    export_path = Path(args.export_file)
    if not export_path.exists():
        print(f"ERROR: export file not found: {export_path}", file=sys.stderr)
        return 1

    rows, first_name, newest_ts = _load_rows(export_path, user_id=args.user_id)
    if not rows:
        print("No importable message rows found in export file.")
        return 0

    last_seen = newest_ts or datetime.utcnow()
    sql = _build_sql(rows, chat_id=args.chat_id, user_id=args.user_id, first_name=first_name, last_seen=last_seen)

    print(f"Loaded {len(rows)} messages from {export_path}")
    print(f"Target chat_id: {args.chat_id}")
    print(f"Last seen timestamp: {last_seen.isoformat()}")

    if args.dry_run:
        print("Dry run enabled; no database changes applied.")
        return 0

    pod_name = _run(
        [
            "kubectl",
            "get",
            "pod",
            "-n",
            args.namespace,
            "-l",
            f"cnpg.io/cluster={args.cluster_name},role=primary",
            "-o",
            "name",
        ]
    )
    if not pod_name:
        print("ERROR: could not find primary CNPG pod", file=sys.stderr)
        return 1

    uri = _run(
        [
            "kubectl",
            "get",
            "secret",
            "-n",
            args.namespace,
            args.secret_name,
            "-o",
            "jsonpath={.data.uri}",
        ]
    )
    if not uri:
        print("ERROR: missing db URI in secret", file=sys.stderr)
        return 1

    decoded_uri = _run(["base64", "-d"], stdin_text=uri)

    _run(
        [
            "kubectl",
            "exec",
            "-i",
            "-n",
            args.namespace,
            pod_name,
            "--",
            "psql",
            decoded_uri,
            "-v",
            "ON_ERROR_STOP=1",
        ],
        stdin_text=sql,
    )

    print("Backfill completed successfully.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())