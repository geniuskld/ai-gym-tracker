from fastapi import APIRouter, HTTPException, status

from app.schemas import SCHEMA_REGISTRY, supported_types_summary

router = APIRouter(tags=["schema"])


@router.get("/schema")
async def get_schema(type: str | None = None):
    if type is None:
        return {"types": supported_types_summary()}

    entry = SCHEMA_REGISTRY.get(type)
    if not entry:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Unknown plan_type '{type}'. Supported: {list(SCHEMA_REGISTRY.keys())}",
        )

    current = entry["current_version"]
    module = entry["versions"][current]
    return module.DESCRIPTION
