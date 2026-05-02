from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.auth import get_current_user, maybe_refresh_token
from app.database import get_db
from app.schemas import PlanType

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

        # Denorm body_part on each strength exercise log entry so analytics
        # queries can group by body_part with a single index hit (no $lookup
        # to plans collection). Cycling logs have segments instead -- skip.
        if w.get("plan_type") == "strength":
            await _enrich_strength_exercises_with_body_part(
                user_id=user["_id"], workout=w
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
    type: PlanType | None = None,
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
        query["plan_type"] = type.value

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


# MARK: - Body-part denorm middleware

async def _enrich_strength_exercises_with_body_part(
    user_id: str,
    workout: dict,
) -> None:
    """Mutates each entry in `workout["exercises"]` adding `body_part`.

    Resolution priority:
      1. `exercise.catalog_id` -> exercises.body_part in catalog
      2. fallback to plans collection lookup by (plan_id, plan_version, exercise_id)
      3. otherwise leave body_part absent
    """
    exercises = workout.get("exercises")
    if not isinstance(exercises, list) or not exercises:
        return

    db = get_db()
    plan_id = workout.get("plan_id")
    plan_version = workout.get("plan_version")

    # Pre-load plan exercises map once if any catalog lookup falls back.
    plan_exercises_by_id: dict[str, str] = {}
    plan_doc_loaded = False

    async def _load_plan_exercises_once() -> None:
        nonlocal plan_doc_loaded
        if plan_doc_loaded:
            return
        plan_doc_loaded = True
        if not (plan_id and plan_version is not None):
            return
        plan_doc = await db.plans.find_one(
            {
                "user_id": user_id,
                "plan_id": plan_id,
                "plan_version": plan_version,
            },
            projection={"templates": 1},
        )
        if not plan_doc:
            return
        for tmpl in plan_doc.get("templates", []) or []:
            for grp in tmpl.get("groups", []) or []:
                for ex in grp.get("exercises", []) or []:
                    ex_id = ex.get("id")
                    bp = ex.get("body_part")
                    if ex_id and bp:
                        plan_exercises_by_id[ex_id] = bp

    for ex_log in exercises:
        if not isinstance(ex_log, dict):
            continue
        if ex_log.get("body_part"):
            # Already populated by client -- respect it.
            continue

        body_part: str | None = None
        cid = ex_log.get("catalog_id")
        if cid:
            cat = await db.exercises.find_one(
                {"slug": cid},
                projection={"body_part": 1, "_id": 0},
            )
            if cat:
                body_part = cat.get("body_part")

        if not body_part:
            await _load_plan_exercises_once()
            ex_id = ex_log.get("exercise_id")
            if ex_id:
                body_part = plan_exercises_by_id.get(ex_id)

        if body_part:
            ex_log["body_part"] = body_part


def _attach_refreshed_token(user: dict, response: Response | None) -> None:
    payload = user.get("_token_payload")
    if payload and response:
        new_token = maybe_refresh_token(payload)
        if new_token:
            response.headers["X-Refreshed-Token"] = new_token
