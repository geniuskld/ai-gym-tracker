from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.auth import get_current_user, maybe_refresh_token
from app.database import get_db
from app.schemas import SCHEMA_REGISTRY, PlanType
from app.schemas.base import validate_base
from app.schemas import strength_v1

router = APIRouter(tags=["plan"])


@router.get("/plans")
async def list_plans(
    type: PlanType | None = None,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    """Return the latest version of each plan (full content) for the user."""
    _attach_refreshed_token(user, response)

    match: dict = {"user_id": user["_id"]}
    if type:
        match["plan_type"] = type.value

    pipeline = [
        {"$match": match},
        {"$sort": {"plan_version": -1}},
        {"$group": {
            "_id": {"plan_id": "$plan_id", "plan_type": "$plan_type"},
            "doc": {"$first": "$$ROOT"},
        }},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$project": {"_id": 0, "user_id": 0}},
        {"$sort": {"plan_name": 1}},
    ]

    results = []
    async for doc in get_db().plans.aggregate(pipeline):
        results.append(doc)
    return results


@router.put("/plan")
async def put_plan(
    request: Request,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    data = await request.json()

    # 1. Base field validation (plan_type, plan_id, plan_version, plan_name, created_at)
    validate_base(data)

    plan_type = data["plan_type"]
    plan_id = data["plan_id"]
    plan_version = data["plan_version"]

    # 2. Schema validation for this plan type
    schema_module = SCHEMA_REGISTRY.get(plan_type)
    if not schema_module:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Unknown plan_type '{plan_type}'. "
                f"Supported: {list(SCHEMA_REGISTRY.keys())}. "
                f"See: /schema"
            ),
        )

    schema_module.validate(data)

    # 3. Version must be greater than existing for this plan_id
    latest = await get_db().plans.find_one(
        {"user_id": user["_id"], "plan_type": plan_type, "plan_id": plan_id},
        sort=[("plan_version", -1)],
        projection={"plan_version": 1},
    )
    if latest and latest["plan_version"] >= plan_version:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"plan_version must be > {latest['plan_version']} "
                f"(current latest for {plan_type}/{plan_id})"
            ),
        )

    # 4. Soft warnings (e.g. missing catalog_id). Strength only for now.
    warnings: list[str] = []
    if plan_type == "strength":
        catalog_slugs = await _load_catalog_slugs("strength")
        warnings = strength_v1.collect_warnings(data, catalog_slugs)

    # 5. Store
    data["user_id"] = user["_id"]
    await get_db().plans.insert_one(data)
    data.pop("_id", None)
    data.pop("user_id", None)

    # 6. Attach warnings to response if any (only when non-empty)
    if warnings:
        data["_warnings"] = warnings
    return data


# MARK: - Helpers

async def _load_catalog_slugs(plan_type: str) -> set[str]:
    """Returns slugs of non-deprecated exercises in the catalog for a plan type."""
    cursor = get_db().exercises.find(
        {"applies_to": plan_type, "deprecated": {"$ne": True}},
        projection={"slug": 1, "_id": 0},
    )
    return {doc["slug"] async for doc in cursor}


def _attach_refreshed_token(user: dict, response: Response | None) -> None:
    payload = user.get("_token_payload")
    if payload and response:
        new_token = maybe_refresh_token(payload)
        if new_token:
            response.headers["X-Refreshed-Token"] = new_token
