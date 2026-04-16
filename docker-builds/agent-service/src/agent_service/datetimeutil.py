"""
Timezone-aware datetime utilities for agent-service.

All times in this module default to PST (Pacific Standard Time).
When displaying times to users, use format_time_for_user() and related functions.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

# PST/PDT timezone (US/Los_Angeles handles DST automatically)
PST = ZoneInfo("America/Los_Angeles")


def now_pst() -> datetime:
    """
    Return current datetime in PST/PDT (Pacific timezone).
    Always timezone-aware.
    """
    return datetime.now(PST)


def format_time_for_user(dt: datetime | None = None, include_date: bool = False) -> str:
    """
    Format a datetime for display to the user in PST.

    If dt is naive (no timezone), treat it as UTC and convert to PST.
    If dt is timezone-aware, convert to PST.
    If dt is None, use current time.

    Args:
        dt: datetime to format, or None for current time
        include_date: if True, include date in format (e.g., "Wed Apr 16 2:30p")

    Returns:
        Human-readable time string in PST (e.g., "2:30 PM" or "Wed Apr 16 2:30 PM")
    """
    if dt is None:
        dt = now_pst()
    elif dt.tzinfo is None:
        # Assume UTC if naive
        dt = dt.replace(tzinfo=timezone.utc)

    # Convert to PST
    dt = dt.astimezone(PST)

    if include_date:
        return dt.strftime("%a %b %d %I:%M %p").lstrip("0").replace(" 0", " ")
    else:
        return dt.strftime("%I:%M %p").lstrip("0")


def format_date_for_user(dt: datetime | None = None) -> str:
    """
    Format a datetime as just a date for user display in PST.

    Args:
        dt: datetime to format, or None for current time

    Returns:
        Date string (e.g., "Wednesday, April 16")
    """
    if dt is None:
        dt = now_pst()
    elif dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)

    dt = dt.astimezone(PST)
    return dt.strftime("%A, %B %d, %Y")


def estimated_time_for_duration(duration_minutes: int | None) -> str:
    """
    Return estimated completion time for a task with given duration.

    Args:
        duration_minutes: duration in minutes

    Returns:
        Human-readable string like "in 30 minutes" or "by 3:30 PM"
    """
    if duration_minutes is None or duration_minutes <= 0:
        return "in a few minutes"

    if duration_minutes < 60:
        minutes = duration_minutes
        return f"in {minutes} minute{'s' if minutes != 1 else ''}"

    now = now_pst()
    completion_time = now + timedelta(minutes=duration_minutes)
    time_str = format_time_for_user(completion_time)
    return f"by {time_str}"


def current_time_context() -> dict[str, str]:
    """
    Return structured context about current time for system prompts.

    Returns:
        dict with keys: date, time, day_of_week, time_of_day
    """
    now = now_pst()
    hour = now.hour

    if hour < 12:
        time_of_day = "morning"
    elif hour < 17:
        time_of_day = "afternoon"
    elif hour < 21:
        time_of_day = "evening"
    else:
        time_of_day = "night"

    return {
        "date": format_date_for_user(now),
        "time": format_time_for_user(now),
        "day_of_week": now.strftime("%A"),
        "time_of_day": time_of_day,
        "hour_24": str(now.hour),
    }


def snooze_until_time(duration_minutes: int) -> str:
    """
    Return a descriptive string of when a snooze will expire.

    Args:
        duration_minutes: snooze duration in minutes

    Returns:
        Human-readable string like "2:30 PM" or "tomorrow at 10 AM"
    """
    now = now_pst()
    snooze_time = now + timedelta(minutes=duration_minutes)

    # If it's more than 24 hours away, include date
    if snooze_time.day != now.day:
        return f"tomorrow at {format_time_for_user(snooze_time)}"
    else:
        return format_time_for_user(snooze_time)

