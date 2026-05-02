"""Sanity checks on the seed JSON files.

These run in pytest without mongo -- they just load the seed files and
verify structural invariants that, if broken, would cause the bootstrap
script to fail or analytics to misbehave.
"""

import json
from pathlib import Path

_TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools" / "seed_data"
SEED_MUSCLES = _TOOLS_DIR / "muscle_groups.json"
SEED_EXERCISES = _TOOLS_DIR / "exercises.json"


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


# --- muscle_groups ---------------------------------------------------------

def test_muscle_groups_seed_loads():
    docs = _load(SEED_MUSCLES)
    assert isinstance(docs, list)
    assert len(docs) >= 15, "expected ~20 muscle groups"


def test_muscle_groups_slugs_unique():
    docs = _load(SEED_MUSCLES)
    slugs = [d["slug"] for d in docs]
    assert len(slugs) == len(set(slugs)), f"duplicate slugs: {slugs}"


def test_muscle_groups_required_fields():
    docs = _load(SEED_MUSCLES)
    for d in docs:
        for f in ("slug", "name", "region", "antagonist_slugs", "aliases"):
            assert f in d, f"muscle '{d.get('slug')}' missing field '{f}'"
        assert d["region"] in {
            "legs", "chest", "back", "shoulders", "arms", "core", "full_body",
        }, f"unexpected region '{d['region']}' in {d['slug']}"


def test_muscle_groups_antagonists_resolve():
    docs = _load(SEED_MUSCLES)
    slugs = {d["slug"] for d in docs}
    for d in docs:
        for ant in d.get("antagonist_slugs", []):
            assert ant in slugs, (
                f"muscle '{d['slug']}' has unknown antagonist '{ant}'"
            )


def test_muscle_aliases_are_english():
    """Aliases should be ASCII-only English strings -- no Russian, no
    other Cyrillic. Models translate user input to English then match."""
    docs = _load(SEED_MUSCLES)
    for d in docs:
        for alias in d.get("aliases", []):
            assert all(ord(c) < 128 for c in alias), (
                f"non-ASCII alias '{alias}' in muscle '{d['slug']}'"
            )


# --- exercises -------------------------------------------------------------

def test_exercises_seed_loads():
    docs = _load(SEED_EXERCISES)
    assert isinstance(docs, list)
    assert len(docs) >= 25, "expected ~30 exercises"


def test_exercises_slugs_unique():
    docs = _load(SEED_EXERCISES)
    slugs = [d["slug"] for d in docs]
    assert len(slugs) == len(set(slugs)), f"duplicate slugs: {slugs}"


def test_exercises_required_fields():
    docs = _load(SEED_EXERCISES)
    for d in docs:
        for f in (
            "slug", "name", "aliases", "body_part", "equipment",
            "movement_pattern", "primary_muscles", "secondary_muscles",
            "applies_to",
        ):
            assert f in d, f"exercise '{d.get('slug')}' missing field '{f}'"


def test_exercise_body_part_enum():
    docs = _load(SEED_EXERCISES)
    valid = {"legs", "chest", "back", "shoulders", "arms", "core", "full_body"}
    for d in docs:
        assert d["body_part"] in valid, (
            f"bad body_part '{d['body_part']}' in {d['slug']}"
        )


def test_exercise_equipment_enum():
    docs = _load(SEED_EXERCISES)
    valid = {
        "machine", "barbell", "dumbbell", "cable", "bodyweight",
        "plate_loaded", "smith_machine", "other",
    }
    for d in docs:
        assert d["equipment"] in valid, (
            f"bad equipment '{d['equipment']}' in {d['slug']}"
        )


def test_exercise_muscles_resolve():
    """Every primary/secondary muscle slug in exercises must exist in muscle_groups."""
    muscles = {m["slug"] for m in _load(SEED_MUSCLES)}
    docs = _load(SEED_EXERCISES)
    for d in docs:
        for m in d.get("primary_muscles", []):
            assert m in muscles, (
                f"exercise '{d['slug']}' references unknown muscle '{m}'"
            )
        for m in d.get("secondary_muscles", []):
            assert m in muscles, (
                f"exercise '{d['slug']}' references unknown muscle '{m}'"
            )


def test_exercise_applies_to_non_empty():
    docs = _load(SEED_EXERCISES)
    for d in docs:
        applies = d.get("applies_to", [])
        assert isinstance(applies, list) and len(applies) > 0, (
            f"exercise '{d['slug']}' has empty applies_to"
        )
        for pt in applies:
            assert pt in {"strength", "cycling"}, (
                f"unknown plan_type '{pt}' in {d['slug']}.applies_to"
            )


def test_exercise_aliases_are_english():
    docs = _load(SEED_EXERCISES)
    for d in docs:
        for alias in d.get("aliases", []):
            assert all(ord(c) < 128 for c in alias), (
                f"non-ASCII alias '{alias}' in exercise '{d['slug']}'"
            )


def test_exercise_name_is_english():
    docs = _load(SEED_EXERCISES)
    for d in docs:
        assert all(ord(c) < 128 for c in d["name"]), (
            f"non-ASCII name '{d['name']}' in '{d['slug']}'"
        )


def test_exercise_slug_snake_case():
    """Convention: lowercase ASCII + underscores + digits only."""
    import re
    pattern = re.compile(r"^[a-z][a-z0-9_]*$")
    docs = _load(SEED_EXERCISES)
    for d in docs:
        assert pattern.match(d["slug"]), (
            f"slug '{d['slug']}' violates snake_case convention"
        )
