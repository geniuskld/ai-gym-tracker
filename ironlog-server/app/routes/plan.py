from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.auth import get_current_user, maybe_refresh_token
from app.database import get_db
from app.schemas import SCHEMA_REGISTRY
from app.schemas.base import validate_base

router = APIRouter(tags=["plan"])


@router.get("/plan")
async def get_plan(
    type: str = "strength",
    id: str | None = None,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    query: dict = {"user_id": user["_id"], "plan_type": type}
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
    type: str = "strength",
    id: str | None = None,
    limit: int = 10,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    query: dict = {"user_id": user["_id"], "plan_type": type}
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
    request: Request,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    data = await request.json()

    # 1. Base validation
    validate_base(data)

    plan_type = data["plan_type"]
    schema_version = data["schema_version"]

    # 2. Check plan_type exists
    registry_entry = SCHEMA_REGISTRY.get(plan_type)
    if not registry_entry:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=f"Unknown plan_type '{plan_type}'. Supported: {list(SCHEMA_REGISTRY.keys())}",
        )

    # 3. Check schema_version is current
    current_version = registry_entry["current_version"]
    if schema_version != current_version:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=(
                f"Schema {plan_type}:{schema_version} not supported. "
                f"Current: {current_version}. "
                f"See: /schema?type={plan_type}"
            ),
        )

    # 4. Type-specific validation
    module = registry_entry["versions"][current_version]
    module.validate(data)

    # 5. Version must be greater than existing
    latest = await get_db().plans.find_one(
        {
            "user_id": user["_id"],
            "plan_type": plan_type,
            "plan_id": data["plan_id"],
        },
        sort=[("plan_version", -1)],
        projection={"plan_version": 1},
    )
    if latest and latest["plan_version"] >= data["plan_version"]:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                f"plan_version must be > {latest['plan_version']} "
                f"(current latest for {plan_type}/{data['plan_id']})"
            ),
        )

    # 6. Insert
    data["user_id"] = user["_id"]
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
