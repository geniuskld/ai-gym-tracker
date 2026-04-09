"""Strength plan schema v1.0 -- validation and description."""

from fastapi import HTTPException, status

VALID_TECHNIQUES = {"straight", "drop_set", "rest_pause", "myo_reps", "superset"}
VALID_BODY_PARTS = {
    "chest", "back", "shoulders", "legs", "arms", "core", "full_body",
}

DESCRIPTION = {
    "plan_type": "strength",
    "schema_version": "1.0",
    "description": "Strength training plan with templates, exercises, and sets",
    "required_base_fields": [
        "plan_type", "plan_id", "plan_version", "plan_name",
        "schema_version", "created_at",
    ],
    "type_specific_fields": {
        "templates": {
            "type": "array (non-empty)",
            "items": {
                "id": "string (unique within plan)",
                "name": "string",
                "exercises": {
                    "type": "array (non-empty)",
                    "items": {
                        "id": "string",
                        "name": "string",
                        "body_part": f"enum: {sorted(VALID_BODY_PARTS)}",
                        "technique": f"enum: {sorted(VALID_TECHNIQUES)}, default: straight",
                        "notes": "string (optional, coach notes)",
                        "sets": {
                            "type": "array (non-empty)",
                            "items": {
                                "reps": "int",
                                "weight_kg": "number (optional)",
                                "rpe": "number (optional)",
                            },
                        },
                    },
                },
            },
        },
    },
    "optional_base_fields": ["author", "notes"],
}


def validate(data: dict) -> None:
    """Validate strength:1.0 type-specific fields."""
    templates = data.get("templates")
    if not isinstance(templates, list) or len(templates) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="templates must be a non-empty array",
        )

    for ti, tmpl in enumerate(templates):
        _require_str(tmpl, "id", f"templates[{ti}]")
        _require_str(tmpl, "name", f"templates[{ti}]")

        exercises = tmpl.get("exercises")
        if not isinstance(exercises, list) or len(exercises) == 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"templates[{ti}].exercises must be a non-empty array",
            )

        for ei, ex in enumerate(exercises):
            prefix = f"templates[{ti}].exercises[{ei}]"
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
                if not isinstance(s.get("reps"), int) or s["reps"] < 1:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"{prefix}.sets[{si}].reps must be a positive integer",
                    )


def _require_str(obj: dict, field: str, prefix: str) -> None:
    val = obj.get(field)
    if not isinstance(val, str) or not val.strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.{field} must be a non-empty string",
        )
