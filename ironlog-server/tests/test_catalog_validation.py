"""Unit tests for the catalog payload validators.

These exercise the same validation logic the POST/PUT endpoints use,
imported from a pure-Python module that does not require app.config /
mongo / auth -- so they run in any venv with just `fastapi` + `pytest`.
"""

import pytest
from fastapi import HTTPException

from app.routes._catalog_validators import (
    SLUG_RE,
    VALID_BODY_PARTS,
    VALID_EQUIPMENT,
    VALID_PLAN_TYPES,
    VALID_REGIONS,
    normalize_exercise,
    normalize_muscle,
    validate_exercise_payload_shape,
    validate_muscle_payload,
)


# MARK: - Slug regex

def test_slug_regex_accepts_canonical_forms():
    for slug in [
        "leg_press_machine",
        "back_squat_barbell",
        "lat_pulldown_cable_underhand",
        "ex1",
        "a_b",
    ]:
        assert SLUG_RE.match(slug), f"should accept {slug!r}"


def test_slug_regex_rejects_bad_forms():
    for slug in [
        "Leg_Press",       # uppercase
        "leg-press",       # hyphen
        "1leg_press",      # leading digit
        "_leg_press",      # leading underscore
        "leg press",       # space
        "",
        "жим",             # cyrillic
    ]:
        assert not SLUG_RE.match(slug), f"should reject {slug!r}"


# MARK: - Exercise payload validation

def _ok_exercise(**overrides):
    base = {
        "slug": "leg_press_machine",
        "name": "Leg Press",
        "aliases": [],
        "body_part": "legs",
        "equipment": "machine",
        "movement_pattern": "knee_dominant",
        "primary_muscles": ["quadriceps"],
        "secondary_muscles": [],
        "applies_to": ["strength"],
    }
    base.update(overrides)
    return base


def test_valid_exercise_passes():
    validate_exercise_payload_shape(_ok_exercise())


def test_exercise_missing_slug_raises():
    p = _ok_exercise()
    del p["slug"]
    with pytest.raises(HTTPException) as exc:
        validate_exercise_payload_shape(p)
    assert exc.value.status_code == 422
    assert "slug" in exc.value.detail


def test_exercise_bad_slug_raises():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_payload_shape(_ok_exercise(slug="Bad-Slug"))
    assert exc.value.status_code == 422


def test_exercise_bad_body_part_raises():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_payload_shape(_ok_exercise(body_part="wings"))
    assert exc.value.status_code == 422
    assert "body_part" in exc.value.detail


def test_exercise_empty_primary_muscles_raises():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_payload_shape(_ok_exercise(primary_muscles=[]))
    assert exc.value.status_code == 422
    assert "primary_muscles" in exc.value.detail


def test_exercise_unknown_plan_type_raises():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_payload_shape(_ok_exercise(applies_to=["yoga"]))
    assert exc.value.status_code == 422
    assert "applies_to" in exc.value.detail


def test_exercise_aliases_must_be_strings():
    with pytest.raises(HTTPException) as exc:
        validate_exercise_payload_shape(_ok_exercise(aliases=["ok", 123]))
    assert exc.value.status_code == 422
    assert "aliases" in exc.value.detail


# MARK: - Muscle group payload validation

def _ok_muscle(**overrides):
    base = {
        "slug": "quadriceps",
        "name": "Quadriceps",
        "region": "legs",
        "antagonist_slugs": ["hamstrings"],
        "aliases": ["quads"],
    }
    base.update(overrides)
    return base


def test_valid_muscle_passes():
    validate_muscle_payload(_ok_muscle())


def test_muscle_missing_slug_raises():
    p = _ok_muscle()
    del p["slug"]
    with pytest.raises(HTTPException) as exc:
        validate_muscle_payload(p)
    assert exc.value.status_code == 422


def test_muscle_bad_region_raises():
    with pytest.raises(HTTPException) as exc:
        validate_muscle_payload(_ok_muscle(region="tail"))
    assert exc.value.status_code == 422


def test_muscle_antagonist_must_be_slug():
    with pytest.raises(HTTPException) as exc:
        validate_muscle_payload(_ok_muscle(antagonist_slugs=["Bad-Slug"]))
    assert exc.value.status_code == 422


# MARK: - Normalization

def test_normalize_exercise_strips_name_and_copies_arrays():
    raw = _ok_exercise(name="  Leg Press  ", aliases=["a", "b"])
    out = normalize_exercise(raw)
    assert out["name"] == "Leg Press"
    assert out["aliases"] == ["a", "b"]
    # Arrays must be COPIES so mutating output does not bleed into input.
    out["primary_muscles"].append("hamstrings")
    assert raw["primary_muscles"] == ["quadriceps"]


def test_normalize_exercise_defaults_applies_to_strength():
    raw = {
        "slug": "x",
        "name": "X",
        "aliases": [],
        "body_part": "legs",
        "equipment": "machine",
        "movement_pattern": "knee_dominant",
        "primary_muscles": ["quadriceps"],
    }
    out = normalize_exercise(raw)
    assert out["applies_to"] == ["strength"]
    assert out["secondary_muscles"] == []


def test_normalize_muscle_strips_name():
    out = normalize_muscle(_ok_muscle(name="  Abdominals  "))
    assert out["name"] == "Abdominals"


# MARK: - Constants sanity

def test_valid_body_parts_match_strength_schema():
    """Catalog body_part enum must match the strength plan schema enum
    so plans validate consistently with the catalog."""
    assert VALID_BODY_PARTS == {
        "legs", "chest", "back", "shoulders", "arms", "core", "full_body",
    }


def test_valid_equipment_match_strength_schema():
    assert "machine" in VALID_EQUIPMENT
    assert "barbell" in VALID_EQUIPMENT
    assert "plate_loaded" in VALID_EQUIPMENT


def test_valid_plan_types_only_strength_and_cycling():
    assert VALID_PLAN_TYPES == {"strength", "cycling"}


def test_muscle_regions_match_body_parts():
    """A muscle's region uses the same enum as plan body_part so a future
    join 'this body_part has these muscles' works without translation."""
    assert VALID_REGIONS == VALID_BODY_PARTS
