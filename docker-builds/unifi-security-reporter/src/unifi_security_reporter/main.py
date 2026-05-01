from __future__ import annotations

import argparse
import collections
import datetime as dt
import email.message
import html
import json
import logging
import os
import smtplib
import socket
import sys
import time
from dataclasses import dataclass
from typing import Any

import paramiko
from prometheus_client import Gauge, start_http_server


LOG = logging.getLogger("unifi_security_reporter")
UTC = dt.timezone.utc


@dataclass(frozen=True)
class Settings:
    unifi_host: str = os.getenv("UNIFI_HOST", "192.168.1.1")
    unifi_ssh_port: int = int(os.getenv("UNIFI_SSH_PORT", "22"))
    unifi_ssh_username: str = os.getenv("UNIFI_SSH_USERNAME", "")
    unifi_ssh_password: str = os.getenv("UNIFI_SSH_PASSWORD", "")
    poll_interval_seconds: int = int(os.getenv("POLL_INTERVAL_SECONDS", "60"))
    metrics_port: int = int(os.getenv("METRICS_PORT", "8080"))
    query_lookback_hours: int = int(os.getenv("QUERY_LOOKBACK_HOURS", "24"))
    top_limit: int = int(os.getenv("TOP_LIMIT", "10"))
    smtp_host: str = os.getenv("SMTP_HOST", "email-smtp.us-west-2.amazonaws.com")
    smtp_port: int = int(os.getenv("SMTP_PORT", "587"))
    smtp_username: str = os.getenv("SMTP_USERNAME", "")
    smtp_password: str = os.getenv("SMTP_PASSWORD", "")
    email_from: str = os.getenv("EMAIL_FROM", "security-reporter@myrobertson.com")
    email_to: str = os.getenv("EMAIL_TO", "roy@myrobertson.com")
    email_subject_prefix: str = os.getenv("EMAIL_SUBJECT_PREFIX", "[homelab security]")


@dataclass(frozen=True)
class ThreatEvent:
    key: str
    severity: str
    status: str
    timestamp: float
    src_ip: str
    dst_ip: str
    device_name: str

    @classmethod
    def from_doc(cls, doc: dict[str, Any]) -> "ThreatEvent":
        params = doc.get("parameters") or {}
        return cls(
            key=str(doc.get("key") or "unknown"),
            severity=str(doc.get("severity") or "unknown").lower(),
            status=str(doc.get("status") or "unknown").lower(),
            timestamp=_mongo_epoch_millis(doc.get("time")),
            src_ip=_param_name(params, "SRC_IP"),
            dst_ip=_param_name(params, "DST_IP"),
            device_name=_param_name(params, "DEVICE"),
        )


def _param_name(params: dict[str, Any], key: str) -> str:
    value = params.get(key) or {}
    return str(value.get("name") or value.get("ip") or value.get("target_id") or "unknown")


def _mongo_epoch_millis(value: Any) -> float:
    if isinstance(value, dict):
        value = value.get("$numberLong") or value.get("$numberInt") or value.get("value") or 0
    if value is None:
        return 0.0
    return float(value) / 1000.0


def _js_string(value: str) -> str:
    return json.dumps(value)


def fetch_events(settings: Settings, lookback_hours: int | None = None) -> list[ThreatEvent]:
    if not settings.unifi_ssh_username or not settings.unifi_ssh_password:
        raise RuntimeError("UNIFI_SSH_USERNAME and UNIFI_SSH_PASSWORD are required")

    lookback_hours = lookback_hours or settings.query_lookback_hours
    since_ms = int((time.time() - lookback_hours * 3600) * 1000)
    query = {
        "time": {"$gte": since_ms},
        "$or": [
            {"key": {"$regex": "THREAT|HONEYPOT|IPS|IDS|MALWARE|SECURITY", "$options": "i"}},
            {"severity": {"$in": ["HIGH", "CRITICAL"]}},
        ],
    }
    projection = {
        "_id": 0,
        "key": 1,
        "time": 1,
        "status": 1,
        "severity": 1,
        "parameters.SRC_IP": 1,
        "parameters.DST_IP": 1,
        "parameters.DEVICE": 1,
    }
    js = (
        "var docs=db.alert.find("
        + _js_string(json.dumps(query))
        + ", "
        + _js_string(json.dumps(projection))
        + ").sort({time:-1}).limit(2000).toArray();"
        + "print(JSON.stringify(docs));"
    )
    # mongo's shell accepts JavaScript objects, not JSON strings, so parse inside the shell.
    js = (
        "var q=JSON.parse(" + _js_string(json.dumps(query)) + ");"
        "var p=JSON.parse(" + _js_string(json.dumps(projection)) + ");"
        "print(JSON.stringify(db.alert.find(q,p).sort({time:-1}).limit(2000).toArray()));"
    )

    output = run_gateway_command(settings, f"mongo --quiet --port 27117 ace --eval {_shell_quote(js)}")
    docs = json.loads(output.strip() or "[]")
    return [ThreatEvent.from_doc(doc) for doc in docs]


def run_gateway_command(settings: Settings, command: str) -> str:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            settings.unifi_host,
            port=settings.unifi_ssh_port,
            username=settings.unifi_ssh_username,
            password=settings.unifi_ssh_password,
            timeout=10,
            banner_timeout=10,
            auth_timeout=10,
            look_for_keys=False,
            allow_agent=False,
        )
        _stdin, stdout, stderr = client.exec_command(command, timeout=30)
        out = stdout.read().decode("utf-8", errors="replace")
        err = stderr.read().decode("utf-8", errors="replace")
        rc = stdout.channel.recv_exit_status()
        if rc != 0:
            raise RuntimeError(f"gateway command failed rc={rc}: {err.strip()}")
        return out
    finally:
        client.close()


def _shell_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


SCRAPE_SUCCESS = Gauge("unifi_security_scrape_success", "Whether the last UniFi security scrape succeeded")
SCRAPE_TIMESTAMP = Gauge("unifi_security_last_scrape_timestamp_seconds", "Unix timestamp of the last UniFi scrape")
LAST_EVENT_TIMESTAMP = Gauge("unifi_security_last_event_timestamp_seconds", "Unix timestamp of the newest security event")
RECENT_EVENTS = Gauge(
    "unifi_security_threat_events_recent",
    "UniFi security event count by window, key, and severity",
    ["window", "key", "severity"],
)
RECENT_UNIQUE_SOURCES = Gauge(
    "unifi_security_unique_sources_recent",
    "Unique source IP count by window and severity",
    ["window", "severity"],
)
RECENT_TARGET_EVENTS = Gauge(
    "unifi_security_target_events_recent",
    "Recent UniFi security events by destination target",
    ["window", "dst_ip", "severity"],
)
RECENT_HONEYPOT_EVENTS = Gauge(
    "unifi_security_honeypot_events_recent",
    "Recent UniFi honeypot-related events by window",
    ["window"],
)


def update_metrics(events: list[ThreatEvent], top_limit: int) -> None:
    now = time.time()
    windows = {"10m": 600, "1h": 3600, "24h": 86400}
    RECENT_EVENTS.clear()
    RECENT_UNIQUE_SOURCES.clear()
    RECENT_TARGET_EVENTS.clear()
    RECENT_HONEYPOT_EVENTS.clear()

    if events:
        LAST_EVENT_TIMESTAMP.set(max(event.timestamp for event in events))
    else:
        LAST_EVENT_TIMESTAMP.set(0)

    for window_name, seconds in windows.items():
        scoped = [event for event in events if now - event.timestamp <= seconds]
        by_key_severity = collections.Counter((event.key, event.severity) for event in scoped)
        for (key, severity), count in by_key_severity.items():
            RECENT_EVENTS.labels(window=window_name, key=key, severity=severity).set(count)

        severities = {event.severity for event in scoped} or {"none"}
        for severity in severities:
            sources = {event.src_ip for event in scoped if event.severity == severity and event.src_ip != "unknown"}
            RECENT_UNIQUE_SOURCES.labels(window=window_name, severity=severity).set(len(sources))

        by_target = collections.Counter((event.dst_ip, event.severity) for event in scoped if event.dst_ip != "unknown")
        for (dst_ip, severity), count in by_target.most_common(top_limit):
            RECENT_TARGET_EVENTS.labels(window=window_name, dst_ip=dst_ip, severity=severity).set(count)

        honeypot_count = sum(1 for event in scoped if "honeypot" in event.key.lower())
        RECENT_HONEYPOT_EVENTS.labels(window=window_name).set(honeypot_count)


def run_exporter(settings: Settings) -> None:
    start_http_server(settings.metrics_port)
    LOG.info("listening for metrics on :%s", settings.metrics_port)
    while True:
        try:
            events = fetch_events(settings)
            update_metrics(events, settings.top_limit)
            SCRAPE_SUCCESS.set(1)
            SCRAPE_TIMESTAMP.set(time.time())
            LOG.info("scraped %s UniFi security events", len(events))
        except Exception:
            LOG.exception("failed to scrape UniFi security events")
            SCRAPE_SUCCESS.set(0)
            SCRAPE_TIMESTAMP.set(time.time())
        time.sleep(settings.poll_interval_seconds)


def send_daily_report(settings: Settings) -> None:
    events = fetch_events(settings, lookback_hours=24)
    subject_date = dt.datetime.now(UTC).astimezone().strftime("%Y-%m-%d")
    subject = f"{settings.email_subject_prefix} daily situational awareness - {subject_date}"
    text_body, html_body = render_report(events)
    msg = email.message.EmailMessage()
    msg["From"] = settings.email_from
    msg["To"] = settings.email_to
    msg["Subject"] = subject
    msg.set_content(text_body)
    msg.add_alternative(html_body, subtype="html")

    if not settings.smtp_username or not settings.smtp_password:
        raise RuntimeError("SMTP_USERNAME and SMTP_PASSWORD are required for email reports")

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=30) as smtp:
        smtp.starttls()
        smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(msg)
    LOG.info("sent daily report to %s with %s events", settings.email_to, len(events))


def render_report(events: list[ThreatEvent]) -> tuple[str, str]:
    now = dt.datetime.now(UTC).astimezone()
    high = [event for event in events if event.severity in {"high", "critical"}]
    by_target = collections.Counter(event.dst_ip for event in high if event.dst_ip != "unknown")
    by_source = collections.Counter(event.src_ip for event in high if event.src_ip != "unknown")
    by_key = collections.Counter(event.key for event in high)
    newest = max((event.timestamp for event in events), default=0)
    newest_text = (
        dt.datetime.fromtimestamp(newest, UTC).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
        if newest
        else "none"
    )
    target_lines = [f"- {dst}: {count}" for dst, count in by_target.most_common(10)] or ["- none"]
    source_lines = [f"- {src}: {count}" for src, count in by_source.most_common(10)] or ["- none"]
    key_lines = [f"- {key}: {count}" for key, count in by_key.most_common(10)] or ["- none"]

    lines = [
        "Homelab security situational awareness",
        f"Generated: {now:%Y-%m-%d %H:%M:%S %Z}",
        "",
        f"High/critical gateway threat blocks in the last 24h: {len(high)}",
        f"Newest security event: {newest_text}",
        "",
        "Top targeted internal IPs:",
        *target_lines,
        "",
        "Top external sources:",
        *source_lines,
        "",
        "Event types:",
        *key_lines,
    ]
    text_body = "\n".join(lines)

    def table(counter: collections.Counter[str], label: str) -> str:
        rows = "".join(
            f"<tr><td>{html.escape(item)}</td><td>{count}</td></tr>"
            for item, count in counter.most_common(10)
        )
        return f"<h3>{label}</h3><table><tr><th>Value</th><th>Count</th></tr>{rows or '<tr><td colspan=\"2\">none</td></tr>'}</table>"

    html_body = f"""
    <html>
      <body>
        <h2>Homelab Security Situational Awareness</h2>
        <p><strong>Generated:</strong> {html.escape(f"{now:%Y-%m-%d %H:%M:%S %Z}")}</p>
        <p><strong>High/critical gateway threat blocks in the last 24h:</strong> {len(high)}</p>
        <p><strong>Newest security event:</strong> {html.escape(newest_text)}</p>
        {table(by_target, "Top targeted internal IPs")}
        {table(by_source, "Top external sources")}
        {table(by_key, "Event types")}
      </body>
    </html>
    """
    return text_body, html_body


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["exporter", "daily-email"])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(message)s")
    socket.setdefaulttimeout(30)
    args = parse_args(argv or sys.argv[1:])
    settings = Settings()
    if args.mode == "exporter":
        run_exporter(settings)
    elif args.mode == "daily-email":
        send_daily_report(settings)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
