"""Unit tests for strength_v1.collect_warnings."""

from app.schemas.strength_v1 import collect_warnings


def _plan_with_exercises(exercises_in_one_group):
    return {
        "plan_type": "strength",
        "plan_id": "p",
        "plan_version": 1,
        "plan_name": "P",
        "created_at": "2026-04-30T00:00:00Z",
        "templates": [{
            "id": "d",
            "name": "Day",
            "groups": [{
                "name": "G",
                "exercises": exercises_in_one_group,
            }],
        }],
    }


# Full known catalog for tests
KNOWN = {"leg_press_machine", "chest_press_machine", "lateral_raise_dumbbell"}


def test_no_warnings_when_all_have_valid_catalog_id():
    plan = _plan_with_exercises([
        {"id": "a1", "name": "Leg press", "body_part": "legs",
         "catalog_id": "leg_press_machine",
         "sets": [{"reps": 12}]},
        {"id": "a2", "name": "Chest press", "body_part": "chest",
         "catalog_id": "chest_press_machine",
         "sets": [{"reps": 12}]},
    ])
    assert collect_warnings(plan, KNOWN) == []


def test_warning_when_catalog_id_missing():
    plan = _plan_with_exercises([
        {"id": "a1", "name": "Leg press", "body_part": "legs",
         "sets": [{"reps": 12}]},
    ])
    warnings = collect_warnings(plan, KNOWN)
    assert len(warnings) == 1
    assert "no catalog_id" in warnings[0]
    assert "(a1)" in warnings[0]


def test_warning_when_catalog_id_unknown():
    plan = _plan_with_exercises([
        {"id": "a1", "name": "X", "body_part": "legs",
         "catalog_id": "made_up_slug_machine",
         "sets": [{"reps": 12}]},
    ])
    warnings = collect_warnings(plan, KNOWN)
    assert len(warnings) == 1
    assert "made_up_slug_machine" in warnings[0]
    assert "not in catalog" in warnings[0]


def test_mix_of_valid_missing_unknown():
    plan = _plan_with_exercises([
        {"id": "a1", "name": "X", "body_part": "legs",
         "catalog_id": "leg_press_machine",
         "sets": [{"reps": 12}]},
        {"id": "a2", "name": "Y", "body_part": "legs",
         "sets": [{"reps": 12}]},
        {"id": "a3", "name": "Z", "body_part": "legs",
         "catalog_id": "phantom_slug",
         "sets": [{"reps": 12}]},
    ])
    warnings = collect_warnings(plan, KNOWN)
    assert len(warnings) == 2
    assert any("(a2)" in w and "no catalog_id" in w for w in warnings)
    assert any("(a3)" in w and "phantom_slug" in w for w in warnings)


def test_empty_catalog_treats_everything_as_unknown():
    """Edge case: if the catalog is empty (e.g. bootstrap not run yet),
    every present catalog_id will be flagged as unknown."""
    plan = _plan_with_exercises([
        {"id": "a1", "name": "X", "body_part": "legs",
         "catalog_id": "leg_press_machine",
         "sets": [{"reps": 12}]},
    ])
    warnings = collect_warnings(plan, set())
    assert len(warnings) == 1
    assert "not in catalog" in warnings[0]


def test_warning_path_format_is_stable():
    """The path format `templates[i].groups[j].exercises[k]` matters --
    it lets the AI / Claude correlate warnings back to plan position."""
    plan = _plan_with_exercises([
        {"id": "a1", "name": "X", "body_part": "legs",
         "sets": [{"reps": 12}]},
    ])
    warnings = collect_warnings(plan, KNOWN)
    assert warnings[0].startswith("templates[0].groups[0].exercises[0]")


def test_does_not_raise_on_malformed_input():
    """collect_warnings must never throw -- it's called after validate(),
    so structurally bad inputs are unreachable, but a defensive `or []`
    pattern in the code handles missing arrays gracefully anyway."""
    # No templates at all
    assert collect_warnings({}, KNOWN) == []
    # Templates is None
    assert collect_warnings({"templates": None}, KNOWN) == []
    # Group has no exercises array
    assert collect_warnings({
        "templates": [{"groups": [{"name": "g"}]}]
    }, KNOWN) == []
