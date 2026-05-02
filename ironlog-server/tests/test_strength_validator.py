"""Unit tests for app.schemas.strength_v1.validate."""

import pytest
from fastapi import HTTPException

from app.schemas.strength_v1 import validate


def _ok_plan(**overrides):
    plan = {
        "plan_type": "strength",
        "plan_id": "p1",
        "plan_version": 1,
        "plan_name": "Test",
        "created_at": "2026-04-27T00:00:00Z",
        "templates": [{
            "id": "d1", "name": "Day 1",
            "groups": [{
                "name": "Legs",
                "exercises": [{
                    "id": "e1", "name": "Leg press",
                    "body_part": "legs",
                    "sets": [{"reps": 12}],
                }]
            }]
        }],
    }
    plan.update(overrides)
    return plan


def test_minimal_valid_plan_passes():
    validate(_ok_plan())


def test_empty_templates_raises():
    with pytest.raises(HTTPException) as exc:
        validate(_ok_plan(templates=[]))
    assert exc.value.status_code == 422


def test_unknown_body_part_raises():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["body_part"] = "wings"
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
    assert "body_part" in exc.value.detail


def test_unknown_technique_raises():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["technique"] = "pyramid"
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
    assert "technique" in exc.value.detail


def test_zero_reps_raises():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = [{"reps": 0}]
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
    assert "reps" in exc.value.detail


def test_empty_sets_raises():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = []
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
    assert "sets" in exc.value.detail


def test_empty_exercises_raises():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"] = []
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
    assert "exercises" in exc.value.detail


# weight_kg accepts both integer and float (fractional plates allowed).

def test_integer_weight_kg_passes():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = [
        {"reps": 12, "weight_kg": 100}
    ]
    validate(plan)


def test_float_weight_kg_passes():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = [
        {"reps": 12, "weight_kg": 102.5}
    ]
    validate(plan)


def test_zero_weight_kg_passes():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = [
        {"reps": 12, "weight_kg": 0}
    ]
    validate(plan)


def test_negative_weight_kg_raises():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = [
        {"reps": 12, "weight_kg": -10}
    ]
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
    assert "weight_kg" in exc.value.detail


def test_string_weight_kg_raises():
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = [
        {"reps": 12, "weight_kg": "100"}
    ]
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
    assert "weight_kg" in exc.value.detail


def test_boolean_weight_kg_raises():
    """Python's bool is a subclass of int -- guard against True being treated as 1."""
    plan = _ok_plan()
    plan["templates"][0]["groups"][0]["exercises"][0]["sets"] = [
        {"reps": 12, "weight_kg": True}
    ]
    with pytest.raises(HTTPException) as exc:
        validate(plan)
    assert exc.value.status_code == 422
