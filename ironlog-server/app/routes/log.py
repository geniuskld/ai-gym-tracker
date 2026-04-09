from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.auth import get_current_user, maybe_refresh_token
from app.database import get_db

router = APIRouter(tags=["log"])


@router.post("/log")
async def post_log(
    request: Request,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    data = await request.json()
    workouts = data.get("workouts")
    if not isinstance(workouts, list) or len(workouts) == 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="workouts must be a non-empty array",
        )

    device_id = request.headers.get("X-Device-Id")
    user_agent = request.headers.get("User-Agent")

    upserted = 0
    for w in workouts:
        workout_id = w.get("id")
        if not workout_id:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Each workout must have an 'id' field",
            )

        doc = {**w, "user_id": user["_id"]}
        if device_id:
            doc["device_id"] = device_id
        if user_agent:
            doc["user_agent"] = user_agent

        await get_db().workout_logs.update_one(
            {"user_id": user["_id"], "id": workout_id},
            {"$set": doc},
            upsert=True,
        )
        upserted += 1

    return {"upserted": upserted}


@router.get("/log")
async def get_log(
    since: str | None = None,
    template_id: str | None = None,
    type: str | None = None,
    limit: int = 50,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    query: dict = {"user_id": user["_id"]}

    if since:
        try:
            since_dt = datetime.fromisoformat(since)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="since must be ISO8601 format",
            )
        query["started_at"] = {"$gte": since_dt.isoformat()}

    if template_id:
        query["template_id"] = template_id

    if type:
        query["plan_type"] = type

    cursor = get_db().workout_logs.find(
        query,
        sort=[("started_at", -1)],
    ).limit(min(limit, 200))

    results = []
    async for doc in cursor:
        doc.pop("_id", None)
        doc.pop("user_id", None)
        results.append(doc)
    return results


@router.delete("/log/{workout_id}")
async def delete_log(
    workout_id: str,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    _attach_refreshed_token(user, response)

    result = await get_db().workout_logs.delete_one(
        {"user_id": user["_id"], "id": workout_id},
    )
    if result.deleted_count == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Workout not found",
        )
    return {"deleted": workout_id}


def _attach_refreshed_token(user: dict, response: Response | None) -> None:
    payload = user.get("_token_payload")
    if payload and response:
        new_token = maybe_refresh_token(payload)
        if new_token:
            response.headers["X-Refreshed-Token"] = new_token
