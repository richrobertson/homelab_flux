from __future__ import annotations

import argparse
import collections
import datetime as dt
import email.message
import html
import json
import logging
import os
import re
import smtplib
import socket
import sys
import time
from dataclasses import dataclass, field
from typing import Any

import paramiko
from prometheus_client import Gauge, start_http_server


LOG = logging.getLogger("unifi_security_reporter")
UTC = dt.timezone.utc


def env_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


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
    gateway_interfaces: str = os.getenv("GATEWAY_INTERFACES", "eth9,eth10")
    smtp_host: str = os.getenv("SMTP_HOST", "email-smtp.us-west-2.amazonaws.com")
    smtp_port: int = int(os.getenv("SMTP_PORT", "587"))
    smtp_username: str = os.getenv("SMTP_USERNAME", "")
    smtp_password: str = os.getenv("SMTP_PASSWORD", "")
    smtp_starttls: bool = env_bool("SMTP_STARTTLS", True)
    smtp_auth_required: bool = env_bool("SMTP_AUTH_REQUIRED", True)
    email_from: str = os.getenv("EMAIL_FROM", "security-reporter@myrobertson.net")
    email_to: str = os.getenv("EMAIL_TO", "roy@myrobertson.com")
    email_subject_prefix: str = os.getenv("EMAIL_SUBJECT_PREFIX", "[homelab security]")
    trend_lookback_days: int = int(os.getenv("TREND_LOOKBACK_DAYS", "60"))
    trend_event_limit: int = int(os.getenv("TREND_EVENT_LIMIT", "20000"))


@dataclass(frozen=True)
class ThreatEvent:
    key: str
    severity: str
    status: str
    timestamp: float
    src_ip: str
    dst_ip: str
    device_name: str
    details: dict[str, str] = field(default_factory=dict)

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
            details=_event_details(doc, params),
        )

    @property
    def event_id(self) -> str:
        return f"{int(self.timestamp * 1000)}:{self.key}:{self.src_ip}:{self.dst_ip}"

    @property
    def timestamp_text(self) -> str:
        return dt.datetime.fromtimestamp(self.timestamp, UTC).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")

    def is_important(self) -> bool:
        return self.severity in {"high", "critical"} or "honeypot" in self.key.lower()

    def to_log_record(self) -> dict[str, Any]:
        return {
            "event_type": "unifi_security_event",
            "event_id": self.event_id,
            "event_time": dt.datetime.fromtimestamp(self.timestamp, UTC).isoformat(),
            "key": self.key,
            "severity": self.severity,
            "status": self.status,
            "src_ip": self.src_ip,
            "dst_ip": self.dst_ip,
            "device_name": self.device_name,
            "details": self.details,
        }

    @property
    def summary(self) -> str:
        return _format_details(self.details)


def _param_name(params: dict[str, Any], key: str) -> str:
    value = _param_value(params, key) or {}
    if isinstance(value, dict):
        return str(value.get("name") or value.get("ip") or value.get("target_id") or "unknown")
    return str(value or "unknown")


def _param_scalar(params: dict[str, Any], key: str) -> str:
    value = _param_value(params, key)
    if isinstance(value, dict):
        value = value.get("name") or value.get("value") or value.get("ip") or value.get("target_id")
    if value in (None, ""):
        return ""
    return str(value)


def _param_value(params: dict[str, Any], key: str) -> Any:
    for candidate in (key, key.upper(), key.lower()):
        if candidate in params:
            return params[candidate]
    normalized = key.replace("_", "").lower()
    for param_key, value in params.items():
        if str(param_key).replace("_", "").lower() == normalized:
            return value
    return None


def _event_details(doc: dict[str, Any], params: dict[str, Any]) -> dict[str, str]:
    fields = {
        "message": doc.get("message") or doc.get("msg") or doc.get("description"),
        "signature": _first_param(params, "SIGNATURE", "SIG_NAME", "THREAT_NAME", "NAME"),
        "category": _first_param(params, "CATEGORY", "CAT", "CLASSIFICATION", "APP_CATEGORY"),
        "protocol": _first_param(params, "PROTOCOL", "PROTO", "L4_PROTO"),
        "source_port": _first_param(params, "SRC_PORT", "SOURCE_PORT", "SPORT"),
        "target_port": _first_param(params, "DST_PORT", "DESTINATION_PORT", "DPORT"),
        "direction": _first_param(params, "DIRECTION", "FLOW_DIRECTION"),
        "action": _first_param(params, "ACTION", "RULE_ACTION"),
        "interface": _first_param(params, "INTERFACE", "IN_INTERFACE", "OUT_INTERFACE"),
    }
    details = {key: str(value) for key, value in fields.items() if value not in (None, "")}
    if details:
        return details

    ignored = {"SRC_IP", "DST_IP", "DEVICE"}
    for key, value in params.items():
        if str(key).upper() in ignored:
            continue
        scalar = _param_scalar(params, str(key))
        if scalar:
            details[str(key).lower()] = scalar
        if len(details) >= 6:
            break
    return details


def _first_param(params: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = _param_scalar(params, key)
        if value:
            return value
    return ""


def _format_details(details: dict[str, str]) -> str:
    if not details:
        return "No additional threat characteristics reported by UniFi"
    labels = {
        "message": "Message",
        "signature": "Signature",
        "category": "Category",
        "protocol": "Protocol",
        "source_port": "Src port",
        "target_port": "Dst port",
        "direction": "Direction",
        "action": "Action",
        "interface": "Interface",
    }
    return "; ".join(f"{labels.get(key, key.replace('_', ' ').title())}: {value}" for key, value in details.items())


def _mongo_epoch_millis(value: Any) -> float:
    if isinstance(value, dict):
        value = value.get("$numberLong") or value.get("$numberInt") or value.get("value") or 0
    if value is None:
        return 0.0
    return float(value) / 1000.0


def _js_string(value: str) -> str:
    return json.dumps(value)


def fetch_events(settings: Settings, lookback_hours: int | None = None, limit: int = 2000) -> list[ThreatEvent]:
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
        "message": 1,
        "msg": 1,
        "description": 1,
        "parameters": 1,
    }
    js = (
        "var docs=db.alert.find("
        + _js_string(json.dumps(query))
        + ", "
        + _js_string(json.dumps(projection))
        + ").sort({time:-1}).limit(" + str(limit) + ").toArray();"
        + "print(JSON.stringify(docs));"
    )
    # mongo's shell accepts JavaScript objects, not JSON strings, so parse inside the shell.
    js = (
        "var q=JSON.parse(" + _js_string(json.dumps(query)) + ");"
        "var p=JSON.parse(" + _js_string(json.dumps(projection)) + ");"
        "print(JSON.stringify(db.alert.find(q,p).sort({time:-1}).limit(" + str(limit) + ").toArray()));"
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


@dataclass(frozen=True)
class GatewayInterfaceStats:
    device: str
    role: str
    operstate_up: float
    speed_bits_per_second: float
    rx_bytes: float
    tx_bytes: float
    rx_packets: float
    tx_packets: float
    rx_errors: float
    tx_errors: float
    rx_dropped: float
    tx_dropped: float


@dataclass(frozen=True)
class GatewayHealth:
    cpu: dict[str, float]
    load1: float
    load5: float
    load15: float
    cpu_cores: float
    mem_total_bytes: float
    mem_available_bytes: float
    interfaces: list[GatewayInterfaceStats]


def fetch_gateway_health(settings: Settings) -> GatewayHealth:
    devices = [item.strip() for item in settings.gateway_interfaces.split(",") if item.strip()]
    safe_devices = [device for device in devices if re.fullmatch(r"[A-Za-z0-9_.:-]+", device)]
    if not safe_devices:
        raise RuntimeError("GATEWAY_INTERFACES did not contain any safe interface names")

    command = r"""
set -eu
echo "LOAD $(cat /proc/loadavg)"
echo "NPROC $(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"
grep -E '^(MemTotal|MemAvailable):' /proc/meminfo | sed 's/^/MEM /'
head -n1 /proc/stat | sed 's/^/CPU /'
for dev in """ + " ".join(_shell_quote(device) for device in safe_devices) + r"""; do
  if [ -d "/sys/class/net/$dev" ]; then
    echo "IFACE $dev"
    cat "/sys/class/net/$dev/operstate" 2>/dev/null | sed "s/^/OPER $dev /" || true
    cat "/sys/class/net/$dev/speed" 2>/dev/null | sed "s/^/SPEED $dev /" || true
    for stat in rx_bytes tx_bytes rx_packets tx_packets rx_errors tx_errors rx_dropped tx_dropped; do
      cat "/sys/class/net/$dev/statistics/$stat" 2>/dev/null | sed "s/^/STAT $dev $stat /" || true
    done
  fi
done
"""
    output = run_gateway_command(settings, command)
    cpu: dict[str, float] = {}
    load1 = load5 = load15 = 0.0
    cpu_cores = 1.0
    mem_total_bytes = mem_available_bytes = 0.0
    iface_data: dict[str, dict[str, float | str]] = {}

    for raw_line in output.splitlines():
        parts = raw_line.split()
        if not parts:
            continue
        if parts[0] == "LOAD" and len(parts) >= 4:
            load1, load5, load15 = float(parts[1]), float(parts[2]), float(parts[3])
        elif parts[0] == "NPROC" and len(parts) >= 2:
            cpu_cores = max(float(parts[1]), 1.0)
        elif parts[:2] == ["MEM", "MemTotal:"] and len(parts) >= 3:
            mem_total_bytes = float(parts[2]) * 1024
        elif parts[:2] == ["MEM", "MemAvailable:"] and len(parts) >= 3:
            mem_available_bytes = float(parts[2]) * 1024
        elif parts[:2] == ["CPU", "cpu"] and len(parts) >= 12:
            labels = ["user", "nice", "system", "idle", "iowait", "irq", "softirq", "steal", "guest", "guest_nice"]
            cpu = {label: float(value) for label, value in zip(labels, parts[2:12])}
        elif parts[0] == "IFACE" and len(parts) >= 2:
            iface_data.setdefault(parts[1], {})
        elif parts[0] == "OPER" and len(parts) >= 3:
            iface_data.setdefault(parts[1], {})["operstate"] = parts[2]
        elif parts[0] == "SPEED" and len(parts) >= 3:
            try:
                speed_mbps = float(parts[2])
            except ValueError:
                speed_mbps = 0.0
            iface_data.setdefault(parts[1], {})["speed_bits_per_second"] = max(speed_mbps, 0.0) * 1_000_000
        elif parts[0] == "STAT" and len(parts) >= 4:
            iface_data.setdefault(parts[1], {})[parts[2]] = float(parts[3])

    interfaces = []
    for device in safe_devices:
        data = iface_data.get(device, {})
        role = "wan" if device == safe_devices[0] else "lan" if len(safe_devices) > 1 and device == safe_devices[1] else "routed"
        interfaces.append(
            GatewayInterfaceStats(
                device=device,
                role=role,
                operstate_up=1.0 if data.get("operstate") == "up" else 0.0,
                speed_bits_per_second=float(data.get("speed_bits_per_second") or 0),
                rx_bytes=float(data.get("rx_bytes") or 0),
                tx_bytes=float(data.get("tx_bytes") or 0),
                rx_packets=float(data.get("rx_packets") or 0),
                tx_packets=float(data.get("tx_packets") or 0),
                rx_errors=float(data.get("rx_errors") or 0),
                tx_errors=float(data.get("tx_errors") or 0),
                rx_dropped=float(data.get("rx_dropped") or 0),
                tx_dropped=float(data.get("tx_dropped") or 0),
            )
        )

    return GatewayHealth(
        cpu=cpu,
        load1=load1,
        load5=load5,
        load15=load15,
        cpu_cores=cpu_cores,
        mem_total_bytes=mem_total_bytes,
        mem_available_bytes=mem_available_bytes,
        interfaces=interfaces,
    )


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
GATEWAY_LOAD = Gauge("unifi_gateway_load_average", "UniFi gateway load average by interval", ["interval"])
GATEWAY_CPU_CORES = Gauge("unifi_gateway_cpu_cores", "UniFi gateway online CPU cores")
GATEWAY_CPU_SECONDS = Gauge("unifi_gateway_cpu_seconds_total", "UniFi gateway cumulative CPU seconds by mode", ["mode"])
GATEWAY_MEMORY_BYTES = Gauge("unifi_gateway_memory_bytes", "UniFi gateway memory by state", ["state"])
GATEWAY_INTERFACE_UP = Gauge("unifi_gateway_interface_up", "UniFi gateway interface operational state", ["device", "role"])
GATEWAY_INTERFACE_SPEED_BITS = Gauge(
    "unifi_gateway_interface_speed_bits",
    "UniFi gateway interface negotiated speed in bits per second",
    ["device", "role"],
)
GATEWAY_INTERFACE_BYTES = Gauge(
    "unifi_gateway_interface_bytes_total",
    "UniFi gateway interface byte counters",
    ["device", "role", "direction"],
)
GATEWAY_INTERFACE_PACKETS = Gauge(
    "unifi_gateway_interface_packets_total",
    "UniFi gateway interface packet counters",
    ["device", "role", "direction"],
)
GATEWAY_INTERFACE_ERRORS = Gauge(
    "unifi_gateway_interface_errors_total",
    "UniFi gateway interface error counters",
    ["device", "role", "direction"],
)
GATEWAY_INTERFACE_DROPS = Gauge(
    "unifi_gateway_interface_drops_total",
    "UniFi gateway interface drop counters",
    ["device", "role", "direction"],
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


def update_gateway_health_metrics(health: GatewayHealth) -> None:
    GATEWAY_LOAD.labels(interval="1m").set(health.load1)
    GATEWAY_LOAD.labels(interval="5m").set(health.load5)
    GATEWAY_LOAD.labels(interval="15m").set(health.load15)
    GATEWAY_CPU_CORES.set(health.cpu_cores)
    for mode, ticks in health.cpu.items():
        GATEWAY_CPU_SECONDS.labels(mode=mode).set(ticks / os.sysconf(os.sysconf_names["SC_CLK_TCK"]))
    GATEWAY_MEMORY_BYTES.labels(state="total").set(health.mem_total_bytes)
    GATEWAY_MEMORY_BYTES.labels(state="available").set(health.mem_available_bytes)
    for iface in health.interfaces:
        GATEWAY_INTERFACE_UP.labels(device=iface.device, role=iface.role).set(iface.operstate_up)
        GATEWAY_INTERFACE_SPEED_BITS.labels(device=iface.device, role=iface.role).set(iface.speed_bits_per_second)
        GATEWAY_INTERFACE_BYTES.labels(device=iface.device, role=iface.role, direction="rx").set(iface.rx_bytes)
        GATEWAY_INTERFACE_BYTES.labels(device=iface.device, role=iface.role, direction="tx").set(iface.tx_bytes)
        GATEWAY_INTERFACE_PACKETS.labels(device=iface.device, role=iface.role, direction="rx").set(iface.rx_packets)
        GATEWAY_INTERFACE_PACKETS.labels(device=iface.device, role=iface.role, direction="tx").set(iface.tx_packets)
        GATEWAY_INTERFACE_ERRORS.labels(device=iface.device, role=iface.role, direction="rx").set(iface.rx_errors)
        GATEWAY_INTERFACE_ERRORS.labels(device=iface.device, role=iface.role, direction="tx").set(iface.tx_errors)
        GATEWAY_INTERFACE_DROPS.labels(device=iface.device, role=iface.role, direction="rx").set(iface.rx_dropped)
        GATEWAY_INTERFACE_DROPS.labels(device=iface.device, role=iface.role, direction="tx").set(iface.tx_dropped)


def emit_important_event_logs(events: list[ThreatEvent], seen_event_ids: set[str]) -> None:
    for event in sorted(events, key=lambda item: item.timestamp):
        if not event.is_important() or event.event_id in seen_event_ids:
            continue
        print(json.dumps(event.to_log_record(), sort_keys=True), flush=True)
        seen_event_ids.add(event.event_id)


def run_exporter(settings: Settings) -> None:
    start_http_server(settings.metrics_port)
    LOG.info("listening for metrics on :%s", settings.metrics_port)
    seen_event_ids: set[str] = set()
    while True:
        try:
            events = fetch_events(settings)
            health = fetch_gateway_health(settings)
            update_metrics(events, settings.top_limit)
            update_gateway_health_metrics(health)
            emit_important_event_logs(events, seen_event_ids)
            SCRAPE_SUCCESS.set(1)
            SCRAPE_TIMESTAMP.set(time.time())
            LOG.info("scraped %s UniFi security events and gateway health", len(events))
        except Exception:
            LOG.exception("failed to scrape UniFi security events")
            SCRAPE_SUCCESS.set(0)
            SCRAPE_TIMESTAMP.set(time.time())
        time.sleep(settings.poll_interval_seconds)


def send_daily_report(settings: Settings) -> None:
    events = fetch_events(settings, lookback_hours=24)
    trend_events = fetch_events(
        settings,
        lookback_hours=settings.trend_lookback_days * 24,
        limit=settings.trend_event_limit,
    )
    subject_date = dt.datetime.now(UTC).astimezone().strftime("%Y-%m-%d")
    subject = f"{settings.email_subject_prefix} daily situational awareness - {subject_date}"
    text_body, html_body = render_report(events, trend_events=trend_events, trend_days=settings.trend_lookback_days)
    msg = email.message.EmailMessage()
    msg["From"] = settings.email_from
    msg["To"] = settings.email_to
    msg["Subject"] = subject
    msg.set_content(text_body)
    msg.add_alternative(html_body, subtype="html")

    if settings.smtp_auth_required and (not settings.smtp_username or not settings.smtp_password):
        raise RuntimeError("SMTP_USERNAME and SMTP_PASSWORD are required for email reports")

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=30) as smtp:
        if settings.smtp_starttls:
            smtp.starttls()
        if settings.smtp_auth_required:
            smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(msg)
    LOG.info(
        "sent daily report to %s with %s events and %s trend events",
        settings.email_to,
        len(events),
        len(trend_events),
    )


def _severity_trend(events: list[ThreatEvent], days: int, now: dt.datetime) -> list[tuple[dt.date, collections.Counter[str]]]:
    end_date = now.date()
    start_date = end_date - dt.timedelta(days=days - 1)
    daily: dict[dt.date, collections.Counter[str]] = {
        start_date + dt.timedelta(days=offset): collections.Counter() for offset in range(days)
    }
    for event in events:
        event_date = dt.datetime.fromtimestamp(event.timestamp, UTC).astimezone().date()
        if start_date <= event_date <= end_date:
            daily[event_date][event.severity or "unknown"] += 1
    return [(day, daily[day]) for day in sorted(daily)]


def _trend_text_lines(trend: list[tuple[dt.date, collections.Counter[str]]]) -> list[str]:
    if not trend:
        return ["- none"]
    lines = []
    for day, counts in trend:
        total = sum(counts.values())
        if not total:
            lines.append(f"- {day.isoformat()}: 0")
            continue
        severities = ", ".join(f"{severity}={count}" for severity, count in _ordered_counts(counts))
        lines.append(f"- {day.isoformat()}: {total} ({severities})")
    return lines


def _ordered_counts(counts: collections.Counter[str]) -> list[tuple[str, int]]:
    order = ["critical", "high", "medium", "low", "unknown"]
    known = [(severity, counts[severity]) for severity in order if counts[severity]]
    other = sorted((severity, count) for severity, count in counts.items() if severity not in order and count)
    return known + other


def _trend_html_chart(trend: list[tuple[dt.date, collections.Counter[str]]]) -> str:
    colors = {
        "critical": "#b91c1c",
        "high": "#f97316",
        "medium": "#eab308",
        "low": "#2563eb",
        "unknown": "#6b7280",
    }
    max_total = max((sum(counts.values()) for _day, counts in trend), default=0)
    legend = " ".join(
        f'<span style="white-space:nowrap;margin-right:12px;"><span style="display:inline-block;width:10px;height:10px;background:{color};"></span> {html.escape(severity.title())}</span>'
        for severity, color in colors.items()
    )
    rows = []
    for day, counts in trend:
        total = sum(counts.values())
        if max_total and total:
            segments = []
            for severity, count in _ordered_counts(counts):
                width = max(2, round((count / max_total) * 100))
                color = colors.get(severity, "#6b7280")
                label = html.escape(f"{severity}: {count}")
                segments.append(
                    f'<span title="{label}" style="display:inline-block;height:14px;width:{width}%;background:{color};"></span>'
                )
            bar = "".join(segments)
        else:
            bar = '<span style="color:#6b7280;">none</span>'
        rows.append(
            "<tr>"
            f"<td>{html.escape(day.isoformat())}</td>"
            f'<td style="text-align:right;">{total}</td>'
            f'<td style="min-width:220px;width:70%;">{bar}</td>'
            "</tr>"
        )
    body_rows = "".join(rows) or '<tr><td colspan="3">none</td></tr>'
    return (
        "<h3>60-day threat count trend by severity</h3>"
        f"<p>{legend}</p>"
        "<table>"
        "<tr><th>Date</th><th>Total</th><th>Severity trend</th></tr>"
        f"{body_rows}"
        "</table>"
    )


def _important_event_row(event: ThreatEvent) -> str:
    return (
        "<tr>"
        f"<td>{html.escape(event.timestamp_text)}</td>"
        f"<td>{html.escape(event.severity.upper())}</td>"
        f"<td>{html.escape(event.summary)}</td>"
        f"<td>{html.escape(event.src_ip)}</td>"
        f"<td>{html.escape(event.dst_ip)}</td>"
        f"<td>{html.escape(event.device_name)}</td>"
        f"<td>{html.escape(event.status)}</td>"
        "</tr>"
    )


def render_report(
    events: list[ThreatEvent],
    trend_events: list[ThreatEvent] | None = None,
    trend_days: int = 60,
) -> tuple[str, str]:
    now = dt.datetime.now(UTC).astimezone()
    high = [event for event in events if event.severity in {"high", "critical"}]
    by_target = collections.Counter(event.dst_ip for event in high if event.dst_ip != "unknown")
    by_source = collections.Counter(event.src_ip for event in high if event.src_ip != "unknown")
    by_key = collections.Counter(event.key for event in high)
    important_events = sorted((event for event in events if event.is_important()), key=lambda item: item.timestamp, reverse=True)[:15]
    trend = _severity_trend(trend_events if trend_events is not None else events, trend_days, now)
    newest = max((event.timestamp for event in events), default=0)
    newest_text = (
        dt.datetime.fromtimestamp(newest, UTC).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
        if newest
        else "none"
    )
    target_lines = [f"- {dst}: {count}" for dst, count in by_target.most_common(10)] or ["- none"]
    source_lines = [f"- {src}: {count}" for src, count in by_source.most_common(10)] or ["- none"]
    key_lines = [f"- {key}: {count}" for key, count in by_key.most_common(10)] or ["- none"]
    important_lines = [
        f"- {event.timestamp_text} {event.severity.upper()} {event.summary} src={event.src_ip} dst={event.dst_ip} device={event.device_name} status={event.status}"
        for event in important_events
    ] or ["- none"]
    trend_lines = _trend_text_lines(trend)

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
        "",
        "Important event details:",
        *important_lines,
        "",
        f"Threat count trend by severity ({trend_days} days):",
        *trend_lines,
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
        {_trend_html_chart(trend)}
        {table(by_target, "Top targeted internal IPs")}
        {table(by_source, "Top external sources")}
        {table(by_key, "Event types")}
        <h3>Important event details</h3>
        <table>
          <tr><th>Time</th><th>Severity</th><th>Characteristics</th><th>Source</th><th>Target</th><th>Device</th><th>Status</th></tr>
          {''.join(_important_event_row(event) for event in important_events) or '<tr><td colspan="7">none</td></tr>'}
        </table>
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
