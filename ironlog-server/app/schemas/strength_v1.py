"""Strength plan schema v1.0 -- validation."""

import json
from pathlib import Path

from fastapi import HTTPException, status

VALID_TECHNIQUES = {"straight", "drop_set", "rest_pause", "myo_reps", "superset"}
VALID_BODY_PARTS = {
    "chest", "back", "shoulders", "legs", "arms", "core", "full_body",
}

# Docker: /schemas (volume mount); local: ../../schemas relative to repo
_DOCKER_PATH = Path("/schemas/strength-plan.import.schema.json")
_LOCAL_PATH = Path(__file__).parents[3] / "schemas" / "strength-plan.import.schema.json"
_SCHEMA_PATH = _DOCKER_PATH if _DOCKER_PATH.exists() else _LOCAL_PATH
DESCRIPTION = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))


def validate(data: dict) -> None:
    """Validate strength:1.0 type-specific fields."""
    templates = data.get("templates")
    if not isinstance(templates, list) or len(templates) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="templates must be a non-empty array",
        )

    for ti, tmpl in enumerate(templates):
        _require_dict(tmpl, f"templates[{ti}]")
        _require_str(tmpl, "id", f"templates[{ti}]")
        _require_str(tmpl, "name", f"templates[{ti}]")

        groups = tmpl.get("groups")
        if not isinstance(groups, list) or len(groups) == 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"templates[{ti}].groups must be a non-empty array",
            )

        for gi, grp in enumerate(groups):
            _require_dict(grp, f"templates[{ti}].groups[{gi}]")
            _require_str(grp, "name", f"templates[{ti}].groups[{gi}]")

            exercises = grp.get("exercises")
            if not isinstance(exercises, list) or len(exercises) == 0:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"templates[{ti}].groups[{gi}].exercises must be a non-empty array",
                )

            for ei, ex in enumerate(exercises):
                prefix = f"templates[{ti}].groups[{gi}].exercises[{ei}]"
                _require_dict(ex, prefix)
                _require_str(ex, "id", prefix)
                _require_str(ex, "name", prefix)

                bp = ex.get("body_part")
                if bp not in VALID_BODY_PARTS:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"{prefix}.body_part must be one of {sorted(VALID_BODY_PARTS)}, got '{bp}'",
                    )

                technique = ex.get("technique", "straight")
                if technique not in VALID_TECHNIQUES:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"{prefix}.technique must be one of {sorted(VALID_TECHNIQUES)}, got '{technique}'",
                    )

                sets = ex.get("sets")
                if not isinstance(sets, list) or len(sets) == 0:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"{prefix}.sets must be a non-empty array",
                    )

                for si, s in enumerate(sets):
                    set_prefix = f"{prefix}.sets[{si}]"
                    _require_dict(s, set_prefix)
                    reps = s.get("reps")
                    if isinstance(reps, bool) or not isinstance(reps, int) or reps < 1:
                        raise HTTPException(
                            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail=f"{set_prefix}.reps must be a positive integer",
                        )
                    # weight_kg is optional; if present it must be a non-negative
                    # number (int or float -- fractional plates allowed).
                    if "weight_kg" in s:
                        wk = s["weight_kg"]
                        # Reject bool (Python bool is subclass of int) and
                        # require numeric non-negative.
                        if isinstance(wk, bool) or not isinstance(wk, (int, float)) or wk < 0:
                            raise HTTPException(
                                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                                detail=f"{prefix}.sets[{si}].weight_kg must be a non-negative number",
                            )


def _require_str(obj: dict, field: str, prefix: str) -> None:
    val = obj.get(field)
    if not isinstance(val, str) or not val.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.{field} must be a non-empty string",
        )


def _require_dict(obj: object, prefix: str) -> None:
    if not isinstance(obj, dict):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix} must be an object",
        )


def collect_warnings(data: dict, known_catalog_slugs: set[str]) -> list[str]:
    """Return non-fatal warnings for a strength plan.

    Currently checks `catalog_id`:
    - missing -> warning that analytics continuity may break
    - present but not in `known_catalog_slugs` -> warning about typo or
      unregistered slug

    Hard errors (missing required fields, bad enums, etc) are still
    raised by `validate()`. This function never raises.
    """
    warnings: list[str] = []
    for ti, tmpl in enumerate(data.get("templates", []) or []):
        for gi, grp in enumerate(tmpl.get("groups", []) or []):
            for ei, ex in enumerate(grp.get("exercises", []) or []):
                prefix = f"templates[{ti}].groups[{gi}].exercises[{ei}]"
                ex_id = ex.get("id", "?")
                cid = ex.get("catalog_id")
                if not cid:
                    warnings.append(
                        f"{prefix} ({ex_id}): no catalog_id -- "
                        "analytics continuity may break across plan versions"
                    )
                elif cid not in known_catalog_slugs:
                    warnings.append(
                        f"{prefix} ({ex_id}): catalog_id '{cid}' not in catalog "
                        "(typo or unregistered exercise)"
                    )
    return warnings
