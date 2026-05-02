"""Unit tests for the analytics math helpers."""

from datetime import datetime, timedelta, timezone

import pytest

from app.routes._analytics_helpers import (
    best_set_of,
    epley_1rm,
    parse_iso,
    relative_delta_pct,
    split_window,
    week_start,
    workout_metrics,
)


# MARK: - epley_1rm

def test_epley_1rm_canonical_values():
    # Canonical literature values for sanity
    assert epley_1rm(100, 1) == pytest.approx(103.33, abs=0.05)
    assert epley_1rm(100, 5) == pytest.approx(116.67, abs=0.05)
    assert epley_1rm(100, 10) == pytest.approx(133.33, abs=0.05)


def test_epley_1rm_smooths_across_rep_ranges():
    """High-rep light set should compute a similar 1RM to low-rep heavy set."""
    a = epley_1rm(60, 15)   # 60 * (1 + 15/30) = 90
    b = epley_1rm(80, 6)    # 80 * (1 + 6/30) = 96
    # Both are in the 90-100 ballpark; analytics line stays smooth.
    assert 80 < a < 100
    assert 90 < b < 100


# MARK: - best_set_of

def test_best_set_of_returns_heaviest():
    sets = [
        {"weight_kg": 60, "reps": 12},
        {"weight_kg": 80, "reps": 6},
        {"weight_kg": 70, "reps": 10},
    ]
    best = best_set_of(sets)
    assert best["weight_kg"] == 80


def test_best_set_of_breaks_weight_ties_by_reps():
    sets = [
        {"weight_kg": 80, "reps": 6},
        {"weight_kg": 80, "reps": 8},  # higher reps at same weight wins
    ]
    assert best_set_of(sets)["reps"] == 8


def test_best_set_of_empty_returns_none():
    assert best_set_of([]) is None


# MARK: - workout_metrics

def test_workout_metrics_filters_invalid_sets():
    sets = [
        {"weight_kg": 60, "reps": 10},   # valid
        {"weight_kg": None, "reps": 10},  # filtered
        {"weight_kg": 70, "reps": 0},     # filtered (reps must be > 0)
        {"weight_kg": -5, "reps": 5},     # filtered (weight must be >= 0)
    ]
    m = workout_metrics(sets)
    assert m["working_sets"] == 1
    assert m["volume"] == 600
    assert m["best_set"]["weight_kg"] == 60


def test_workout_metrics_handles_empty():
    m = workout_metrics([])
    assert m == {
        "volume": 0.0, "est_1rm": None, "best_set": None, "working_sets": 0,
    }


def test_workout_metrics_volume_and_est_1rm():
    sets = [
        {"weight_kg": 100, "reps": 12},
        {"weight_kg": 100, "reps": 10},
        {"weight_kg": 100, "reps": 8},
    ]
    m = workout_metrics(sets)
    assert m["volume"] == 100 * 12 + 100 * 10 + 100 * 8
    # Highest est_1rm comes from the highest-rep set at this weight
    assert m["est_1rm"] == pytest.approx(100 * (1 + 12 / 30))


# MARK: - relative_delta_pct

def test_relative_delta_pct_positive():
    assert relative_delta_pct(110, 100) == 10.0


def test_relative_delta_pct_negative():
    assert relative_delta_pct(80, 100) == -20.0


def test_relative_delta_pct_no_change():
    assert relative_delta_pct(100, 100) == 0.0


def test_relative_delta_pct_none_prior():
    assert relative_delta_pct(100, None) is None


def test_relative_delta_pct_zero_prior_is_none():
    """Avoid division by zero AND avoid misleading 'inf%' display."""
    assert relative_delta_pct(100, 0) is None


def test_relative_delta_pct_rounded_to_2_decimals():
    assert relative_delta_pct(123.456, 100) == 23.46


# MARK: - split_window

def test_split_window_basic():
    now = datetime(2026, 4, 30, tzinfo=timezone.utc)
    points = [
        # Recent window (last 30d): days 5 ago
        {"date": (now - timedelta(days=5)).isoformat(), "value": 100},
        # Recent: 25 ago
        {"date": (now - timedelta(days=25)).isoformat(), "value": 50},
        # Prior window (30-60d ago): 45 ago
        {"date": (now - timedelta(days=45)).isoformat(), "value": 80},
        # Outside window: 90 ago
        {"date": (now - timedelta(days=90)).isoformat(), "value": 999},
    ]
    recent, prior = split_window(points, days=30, now=now)
    assert recent == 150
    assert prior == 80


def test_split_window_no_prior_returns_none():
    """If no points fall in the prior window, return None (not 0) so the
    delta can be rendered as 'no comparison' instead of 'inf%'."""
    now = datetime(2026, 4, 30, tzinfo=timezone.utc)
    points = [
        {"date": (now - timedelta(days=5)).isoformat(), "value": 100},
    ]
    recent, prior = split_window(points, days=30, now=now)
    assert recent == 100
    assert prior is None


def test_split_window_handles_naive_datetime_in_input():
    """Logs may have naive ISO strings; the helper must coerce to UTC."""
    now = datetime(2026, 4, 30, tzinfo=timezone.utc)
    points = [
        {"date": "2026-04-25T12:00:00", "value": 100},  # 5 days ago, naive
    ]
    recent, prior = split_window(points, days=30, now=now)
    assert recent == 100


# MARK: - week_start

def test_week_start_returns_monday():
    # 2026-04-30 is a Thursday
    monday = week_start(datetime(2026, 4, 30, tzinfo=timezone.utc))
    assert monday.weekday() == 0
    assert monday.isoformat() == "2026-04-27"


def test_week_start_idempotent_on_monday():
    monday_input = datetime(2026, 4, 27, tzinfo=timezone.utc)
    assert week_start(monday_input).isoformat() == "2026-04-27"


# MARK: - parse_iso

def test_parse_iso_accepts_z_suffix():
    d = parse_iso("2026-04-30T12:00:00Z")
    assert d.tzinfo is not None
    assert d.year == 2026


def test_parse_iso_accepts_offset_suffix():
    d = parse_iso("2026-04-30T12:00:00+02:00")
    assert d.tzinfo is not None
