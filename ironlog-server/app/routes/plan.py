from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.auth import get_current_user, maybe_refresh_token
from app.database import get_db
from app.schemas import SCHEMA_REGISTRY, PlanType
from app.schemas.base import validate_base

router = APIRouter(tags=["plan"])


@router.get("/plans")
async def list_plans(
    type: PlanType | None = None,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    pipeline = [
        {"$match": {"user_id": user["_id"], **({"plan_type": type.value} if type else {})}},
        {"$sort": {"plan_version": -1}},
        {"$group": {
            "_id": {"plan_id": "$plan_id", "plan_type": "$plan_type"},
            "plan_name": {"$first": "$plan_name"},
            "plan_version": {"$first": "$plan_version"},
            "created_at": {"$first": "$created_at"},
            "author": {"$first": "$author"},
        }},
        {"$project": {
            "_id": 0,
            "plan_id": "$_id.plan_id",
            "plan_type": "$_id.plan_type",
            "plan_name": 1,
            "plan_version": 1,
            "created_at": 1,
            "author": 1,
        }},
        {"$sort": {"plan_name": 1}},
    ]

    results = []
    async for doc in get_db().plans.aggregate(pipeline):
        results.append(doc)
    return results


@router.get("/plan")
async def get_plan(
    type: PlanType = PlanType.strength,
    id: str | None = None,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    query: dict = {"user_id": user["_id"], "plan_type": type.value}
    if id:
        query["plan_id"] = id

    doc = await get_db().plans.find_one(
        query,
        sort=[("plan_version", -1)],
    )
    if not doc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No plan found",
        )
    doc.pop("_id", None)
    doc.pop("user_id", None)
    return doc


@router.get("/plan/versions")
async def get_plan_versions(
    type: PlanType = PlanType.strength,
    id: str | None = None,
    limit: int = 10,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    query: dict = {"user_id": user["_id"], "plan_type": type.value}
    if id:
        query["plan_id"] = id

    cursor = get_db().plans.find(
        query,
        sort=[("plan_version", -1)],
    ).limit(limit)

    results = []
    async for doc in cursor:
        doc.pop("_id", None)
        doc.pop("user_id", None)
        results.append(doc)
    return results


@router.put("/plan")
async def put_plan(
    type: PlanType,
    request: Request,
    user: dict = Depends(get_current_user),
    response: Response = None,
    id: str | None = None,
):
    _attach_refreshed_token(user, response)

    data = await request.json()
    plan_type = type.value

    # 1. Base field validation (version, plan_name, created_at, templates)
    validate_base(data)

    # 2. Schema validation for this plan type
    schema_module = SCHEMA_REGISTRY.get(plan_type)
    if not schema_module:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown plan type '{plan_type}'. Supported: {list(SCHEMA_REGISTRY.keys())}",
        )

    schema_module.validate(data)

    # 3. Resolve plan_id: from query param, or auto-generate
    plan_id = id or str(uuid4())

    # 4. plan_version: from body, default to 1
    plan_version = data.get("plan_version", 1)

    # 5. Version must be greater than existing for this plan_id
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

    # 6. Store with server metadata
    data["user_id"] = user["_id"]
    data["plan_type"] = plan_type
    data["plan_id"] = plan_id
    data["plan_version"] = plan_version

    await get_db().plans.insert_one(data)
    data.pop("_id", None)
    data.pop("user_id", None)
    return data


def _attach_refreshed_token(user: dict, response: Response | None) -> None:
    payload = user.get("_token_payload")
    if payload and response:
        new_token = maybe_refresh_token(payload)
        if new_token:
            response.headers["X-Refreshed-Token"] = new_token
