"""Unit tests for app.schemas.cycling_v1.validate."""

import pytest
from fastapi import HTTPException

from app.schemas.cycling_v1 import validate


def _minimal_template(**overrides):
    base = {
        "id": "w1",
        "name": "Week 1",
        "segments": [
            {
                "kind": "warmup",
                "name": "Warmup",
                "duration_seconds": 600,
                "target": {"type": "hr_bpm_range", "min": 110, "max": 125},
            }
        ],
    }
    base.update(overrides)
    return base


def _plan_with(templates):
    return {
        "plan_type": "cycling",
        "plan_id": "test",
        "plan_version": 1,
        "plan_name": "Test",
        "created_at": "2026-04-27T00:00:00Z",
        "templates": templates,
    }


def test_minimal_valid_plan_passes():
    validate(_plan_with([_minimal_template()]))


def test_empty_templates_raises():
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([]))
    assert exc.value.status_code == 422
    assert "templates" in exc.value.detail


def test_unknown_segment_kind_raises():
    bad = _minimal_template(segments=[
        {"kind": "spinning", "name": "S", "duration_seconds": 60,
         "target": {"type": "free"}}
    ])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "kind" in exc.value.detail


def test_leaf_without_duration_raises():
    bad = _minimal_template(segments=[
        {"kind": "warmup", "name": "W",
         "target": {"type": "hr_bpm_range", "min": 110, "max": 125}}
    ])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "duration_seconds" in exc.value.detail


def test_leaf_without_target_raises():
    bad = _minimal_template(segments=[
        {"kind": "warmup", "name": "W", "duration_seconds": 60}
    ])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "target" in exc.value.detail


def test_target_min_greater_than_max_raises():
    bad = _minimal_template(segments=[
        {"kind": "warmup", "name": "W", "duration_seconds": 60,
         "target": {"type": "hr_bpm_range", "min": 200, "max": 100}}
    ])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "min" in exc.value.detail


def test_unknown_target_type_raises():
    bad = _minimal_template(segments=[
        {"kind": "warmup", "name": "W", "duration_seconds": 60,
         "target": {"type": "watts", "min": 100, "max": 200}}
    ])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "type" in exc.value.detail


def test_interval_block_without_repeats_raises():
    bad = _minimal_template(segments=[{
        "kind": "interval_block",
        "name": "Block",
        "children": [
            {"kind": "work", "name": "W", "duration_seconds": 60,
             "target": {"type": "free"}}
        ],
    }])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "repeats" in exc.value.detail


def test_interval_block_with_duration_raises():
    """Block segments must NOT have duration/target -- those are leaf-only."""
    bad = _minimal_template(segments=[{
        "kind": "interval_block",
        "name": "Block",
        "repeats": 2,
        "duration_seconds": 60,
        "children": [
            {"kind": "work", "name": "W", "duration_seconds": 60,
             "target": {"type": "free"}}
        ],
    }])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "duration_seconds" in exc.value.detail


def test_nested_interval_block_raises():
    """Max nesting depth is 1 -- a block inside a block must be rejected."""
    bad = _minimal_template(segments=[{
        "kind": "interval_block",
        "name": "Outer",
        "repeats": 2,
        "children": [{
            "kind": "interval_block",
            "name": "Inner",
            "repeats": 3,
            "children": [
                {"kind": "work", "name": "W", "duration_seconds": 60,
                 "target": {"type": "free"}}
            ],
        }],
    }])
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "nested" in exc.value.detail.lower()


def test_unknown_equipment_raises():
    bad = _minimal_template(equipment="rowing_machine")
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "equipment" in exc.value.detail


def test_progression_axis_unknown_raises():
    bad = _minimal_template(progression={"axis": "weight"})
    with pytest.raises(HTTPException) as exc:
        validate(_plan_with([bad]))
    assert exc.value.status_code == 422
    assert "axis" in exc.value.detail


def test_full_norwegian_4x4_passes():
    """Smoke test mirroring the actual production sample plan shape."""
    plan = _plan_with([
        {
            "id": "week3plus-4x4",
            "name": "Week 3+: Norwegian 4x4",
            "equipment": "stationary_bike",
            "progression": {
                "axis": "intervals",
                "step": {"intervals_delta": 1, "hr_bpm_delta": 5},
                "advance_when": "after 2 sessions in zone",
            },
            "segments": [
                {"kind": "warmup", "name": "WU", "duration_seconds": 600,
                 "target": {"type": "hr_bpm_range", "min": 110, "max": 125,
                            "zone_label": "Z2"}},
                {"kind": "interval_block", "name": "4x4", "repeats": 4,
                 "children": [
                     {"kind": "work", "name": "Work", "duration_seconds": 240,
                      "target": {"type": "hr_bpm_range",
                                 "min": 150, "max": 160}},
                     {"kind": "recovery", "name": "Rec",
                      "duration_seconds": 180,
                      "target": {"type": "hr_bpm_range",
                                 "min": 110, "max": 120}},
                 ]},
                {"kind": "cooldown", "name": "CD", "duration_seconds": 300,
                 "target": {"type": "hr_bpm_range", "min": 90, "max": 110}},
            ],
        }
    ])
    validate(plan)
