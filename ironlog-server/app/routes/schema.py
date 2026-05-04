from fastapi import APIRouter, HTTPException, status

from app.schemas import SCHEMA_REGISTRY, PlanType

router = APIRouter(tags=["schema"])


@router.get("/schema")
async def get_schema(type: PlanType | None = None):
    if type is None:
        return {"types": list(SCHEMA_REGISTRY.keys())}

    module = SCHEMA_REGISTRY.get(type.value)
    if not module:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown plan type '{type.value}'. Supported: {list(SCHEMA_REGISTRY.keys())}",
        )

    description = getattr(module, "DESCRIPTION", None)
    if description is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Schema module for '{type.value}' has no DESCRIPTION",
        )
    return description
