"""Cycling plan schema v1.0 -- validation."""

import json
from pathlib import Path

from fastapi import HTTPException, status

VALID_EQUIPMENT = {"stationary_bike", "spin_bike", "outdoor_bike"}
LEAF_KINDS = {"warmup", "work", "recovery", "cooldown", "steady"}
BLOCK_KIND = "interval_block"
VALID_KINDS = LEAF_KINDS | {BLOCK_KIND}
VALID_TARGET_TYPES = {"hr_bpm_range", "rpe", "free"}
VALID_PROGRESSION_AXIS = {"intervals", "work_duration", "intensity_hr", "manual"}

# Docker: /schemas (volume mount); local: ../../schemas relative to repo
_DOCKER_PATH = Path("/schemas/cycling-plan.import.schema.json")
_LOCAL_PATH = Path(__file__).parents[3] / "schemas" / "cycling-plan.import.schema.json"
_SCHEMA_PATH = _DOCKER_PATH if _DOCKER_PATH.exists() else _LOCAL_PATH
try:
    DESCRIPTION = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
except OSError as exc:
    raise RuntimeError(f"Cycling schema file not found at {_SCHEMA_PATH}") from exc


def validate(data: dict) -> None:
    """Validate cycling:1.0 type-specific fields."""
    templates = data.get("templates")
    if not isinstance(templates, list) or len(templates) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="templates must be a non-empty array",
        )

    for ti, tmpl in enumerate(templates):
        prefix = f"templates[{ti}]"
        _require_dict(tmpl, prefix)
        _require_str(tmpl, "id", prefix)
        _require_str(tmpl, "name", prefix)

        if "equipment" in tmpl:
            eq = tmpl["equipment"]
            if eq not in VALID_EQUIPMENT:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"{prefix}.equipment must be one of {sorted(VALID_EQUIPMENT)}, got '{eq}'",
                )

        if "progression" in tmpl:
            _validate_progression(tmpl["progression"], f"{prefix}.progression")

        segments = tmpl.get("segments")
        if not isinstance(segments, list) or len(segments) == 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{prefix}.segments must be a non-empty array",
            )

        for si, seg in enumerate(segments):
            _validate_segment(seg, f"{prefix}.segments[{si}]", allow_block=True)


def _validate_segment(seg: dict, prefix: str, allow_block: bool) -> None:
    _require_dict(seg, prefix)
    _require_str(seg, "name", prefix)
    kind = seg.get("kind")
    if kind not in VALID_KINDS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.kind must be one of {sorted(VALID_KINDS)}, got '{kind}'",
        )

    if kind == BLOCK_KIND:
        if not allow_block:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{prefix}: nested interval_block not allowed (max nesting depth = 1)",
            )
        for forbidden in ("duration_seconds", "target"):
            if forbidden in seg:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"{prefix}.{forbidden} not allowed for kind=interval_block",
                )
        repeats = seg.get("repeats")
        if isinstance(repeats, bool) or not isinstance(repeats, int) or repeats < 1:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{prefix}.repeats must be a positive integer",
            )
        children = seg.get("children")
        if not isinstance(children, list) or len(children) == 0:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{prefix}.children must be a non-empty array",
            )
        for ci, child in enumerate(children):
            _validate_segment(child, f"{prefix}.children[{ci}]", allow_block=False)
        return

    # Leaf segment
    for forbidden in ("repeats", "children"):
        if forbidden in seg:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{prefix}.{forbidden} not allowed for kind={kind}",
            )
    duration = seg.get("duration_seconds")
    if isinstance(duration, bool) or not isinstance(duration, int) or duration < 1:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.duration_seconds must be a positive integer",
        )
    target = seg.get("target")
    _validate_target(target, f"{prefix}.target")


def _validate_target(target: dict, prefix: str) -> None:
    _require_dict(target, prefix)
    ttype = target.get("type")
    if ttype not in VALID_TARGET_TYPES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.type must be one of {sorted(VALID_TARGET_TYPES)}, got '{ttype}'",
        )
    if ttype in {"hr_bpm_range", "rpe"}:
        for field in ("min", "max"):
            v = target.get(field)
            if isinstance(v, bool) or not isinstance(v, int):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"{prefix}.{field} must be an integer for type={ttype}",
                )
        if target["min"] > target["max"]:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{prefix}.min must be <= {prefix}.max",
            )
    if "zone_label" in target and not isinstance(target["zone_label"], str):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.zone_label must be a string",
        )


def _validate_progression(prog: dict, prefix: str) -> None:
    _require_dict(prog, prefix)
    if "axis" in prog and prog["axis"] not in VALID_PROGRESSION_AXIS:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.axis must be one of {sorted(VALID_PROGRESSION_AXIS)}, got '{prog['axis']}'",
        )
    if "advance_when" in prog and not isinstance(prog["advance_when"], str):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"{prefix}.advance_when must be a string",
        )
    if "step" in prog:
        step = prog["step"]
        if not isinstance(step, dict):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"{prefix}.step must be an object",
            )
        for field in ("intervals_delta", "work_duration_seconds", "hr_bpm_delta"):
            if field in step and (
                isinstance(step[field], bool) or not isinstance(step[field], int)
            ):
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"{prefix}.step.{field} must be an integer",
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
