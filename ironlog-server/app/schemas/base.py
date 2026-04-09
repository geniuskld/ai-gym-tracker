from fastapi import HTTPException, status


REQUIRED_FIELDS = [
    "plan_type",
    "plan_id",
    "plan_version",
    "plan_name",
    "schema_version",
    "created_at",
]


def validate_base(data: dict) -> None:
    """Validate shared base contract fields. Raises HTTPException on failure."""
    missing = [f for f in REQUIRED_FIELDS if f not in data]
    if missing:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Missing required fields: {', '.join(missing)}",
        )

    if not isinstance(data["plan_version"], int) or data["plan_version"] < 1:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="plan_version must be a positive integer",
        )

    if not isinstance(data["plan_id"], str) or not data["plan_id"].strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="plan_id must be a non-empty string",
        )

    if not isinstance(data["plan_name"], str) or not data["plan_name"].strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="plan_name must be a non-empty string",
        )
