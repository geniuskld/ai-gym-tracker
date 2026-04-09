from fastapi import HTTPException, status

REQUIRED_FIELDS = ["plan_name", "created_at"]


def validate_base(data: dict) -> None:
    """Validate base plan fields present in the request body."""
    missing = [f for f in REQUIRED_FIELDS if f not in data]
    if missing:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Missing required fields: {', '.join(missing)}",
        )

    if not isinstance(data["plan_name"], str) or not data["plan_name"].strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="plan_name must be a non-empty string",
        )
