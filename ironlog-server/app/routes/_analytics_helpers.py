"""Pure-Python helpers for strength analytics.

Lives in its own module (no project-internal imports) so unit tests can
exercise the math without spinning up `app.config` / mongo / auth.
"""

from datetime import date, datetime, timedelta, timezone
from typing import Iterable


# MARK: - Per-set / per-workout math

def epley_1rm(weight: float, reps: int) -> float:
    """Estimated 1-rep max via Epley: weight * (1 + reps / 30).

    Smooths comparison across rep ranges. 60 kg x 15 reps and 100 kg x 6
    reps both produce ~115 kg estimated 1RM, so a 12-week progression
    that jumps between rep schemes still shows as a clean line.
    """
    return weight * (1.0 + reps / 30.0)


def best_set_of(sets: Iterable[dict]) -> dict | None:
    """Returns the "headline" set for a workout: the heaviest by weight,
    ties broken by reps. None if there are no usable sets."""
    sets = list(sets)
    if not sets:
        return None
    return max(
        sets,
        key=lambda s: (s.get("weight_kg") or 0, s.get("reps") or 0),
    )


def workout_metrics(working_sets: Iterable[dict]) -> dict:
    """Roll up a list of `{weight_kg, reps}` (working sets only) into the
    per-workout headline numbers we expose to clients.

    - `volume`        = sum(weight * reps)
    - `est_1rm`       = max Epley across sets (None if no usable data)
    - `best_set`      = heaviest set
    - `working_sets`  = count of usable sets
    """
    valid = [
        s for s in working_sets
        if isinstance(s.get("weight_kg"), (int, float))
        and isinstance(s.get("reps"), int)
        and s["weight_kg"] >= 0
        and s["reps"] > 0
    ]
    if not valid:
        return {
            "volume": 0.0,
            "est_1rm": None,
            "best_set": None,
            "working_sets": 0,
        }
    return {
        "volume": float(sum(s["weight_kg"] * s["reps"] for s in valid)),
        "est_1rm": max(epley_1rm(s["weight_kg"], s["reps"]) for s in valid),
        "best_set": {
            "weight_kg": best_set_of(valid)["weight_kg"],
            "reps": best_set_of(valid)["reps"],
        },
        "working_sets": len(valid),
    }


# MARK: - Relative deltas (the "headline numbers")

def relative_delta_pct(recent: float, prior: float | None) -> float | None:
    """`(recent - prior) / prior * 100`, rounded to 2 decimals.

    Returns None when `prior` is None or zero -- the front-end should
    render that as "no comparison data" rather than a misleading number.
    """
    if prior is None or prior == 0:
        return None
    return round((recent - prior) / prior * 100.0, 2)


def split_window(
    points: Iterable[dict],
    *,
    days: int,
    now: datetime,
) -> tuple[float, float | None]:
    """Split a sorted-by-date list of `{date, value}` points into two
    consecutive windows of length `days` ending at `now`, and return the
    sum of `value` in each.

    Recent window: (now - days, now]
    Prior window:  (now - 2*days, now - days]

    `prior` is None if no points fall in that window (analytics shouldn't
    fabricate a baseline of zero).
    """
    cutoff_recent = now - timedelta(days=days)
    cutoff_prior = now - timedelta(days=2 * days)
    recent_total = 0.0
    prior_total = 0.0
    has_prior = False

    for p in points:
        d = p["date"]
        if isinstance(d, str):
            d = datetime.fromisoformat(d.replace("Z", "+00:00"))
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        v = p.get("value", 0)
        if v is None:
            continue
        if d > cutoff_recent:
            recent_total += float(v)
        elif d > cutoff_prior:
            prior_total += float(v)
            has_prior = True

    return recent_total, (prior_total if has_prior else None)


# MARK: - Date helpers

def week_start(d: datetime) -> date:
    """ISO Monday of the week containing `d`. Used for weekly volume bins."""
    if d.tzinfo is None:
        d = d.replace(tzinfo=timezone.utc)
    monday = d - timedelta(days=d.weekday())
    return monday.date()


def parse_iso(s: str) -> datetime:
    """Forgiving ISO 8601 parser: accepts trailing Z."""
    return datetime.fromisoformat(s.replace("Z", "+00:00"))
