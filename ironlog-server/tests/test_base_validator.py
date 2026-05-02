"""Unit tests for app.schemas.base.validate_base."""

import pytest
from fastapi import HTTPException

from app.schemas.base import validate_base, REQUIRED_FIELDS


def _ok_payload(**overrides):
    base = {
        "plan_type": "strength",
        "plan_id": "p1",
        "plan_version": 1,
        "plan_name": "Test plan",
        "created_at": "2026-04-27T00:00:00Z",
    }
    base.update(overrides)
    return base


def test_valid_payload_passes():
    validate_base(_ok_payload())


@pytest.mark.parametrize("missing_field", REQUIRED_FIELDS)
def test_missing_required_field_raises_422(missing_field):
    payload = _ok_payload()
    payload.pop(missing_field)
    with pytest.raises(HTTPException) as exc:
        validate_base(payload)
    assert exc.value.status_code == 422
    assert missing_field in exc.value.detail


def test_empty_plan_name_raises():
    with pytest.raises(HTTPException) as exc:
        validate_base(_ok_payload(plan_name="   "))
    assert exc.value.status_code == 422
    assert "plan_name" in exc.value.detail


def test_empty_plan_id_raises():
    with pytest.raises(HTTPException) as exc:
        validate_base(_ok_payload(plan_id=""))
    assert exc.value.status_code == 422
    assert "plan_id" in exc.value.detail


def test_non_int_plan_version_raises():
    with pytest.raises(HTTPException) as exc:
        validate_base(_ok_payload(plan_version="1"))
    assert exc.value.status_code == 422
    assert "plan_version" in exc.value.detail


def test_zero_plan_version_raises():
    with pytest.raises(HTTPException) as exc:
        validate_base(_ok_payload(plan_version=0))
    assert exc.value.status_code == 422
