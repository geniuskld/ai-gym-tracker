from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from app.auth import get_current_user, maybe_refresh_token
from app.database import get_db

router = APIRouter(tags=["crash"])


@router.post("/crash")
async def post_crash(
    request: Request,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    """Receive a crash report from the client and store it.

    The body is whatever JSON the client produced. We do not validate
    field-by-field: the goal is to capture as much as possible even
    if the format evolves. We only enforce that the body is an object.
    """
    _attach_refreshed_token(user, response)

    try:
        data = await request.json()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Body must be valid JSON",
        )

    if not isinstance(data, dict):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Body must be a JSON object",
        )

    doc = {
        **data,
        "user_id": user["_id"],
        "received_at": datetime.now(timezone.utc).isoformat(),
    }
    if device_id := request.headers.get("X-Device-Id"):
        doc["device_id"] = device_id
    if user_agent := request.headers.get("User-Agent"):
        doc["user_agent"] = user_agent

    await get_db().crash_logs.insert_one(doc)
    doc.pop("_id", None)
    return {"ok": True, "id": data.get("id")}


@router.get("/crashes")
async def list_crashes(
    limit: int = 50,
    user: dict = Depends(get_current_user),
    response: Response = None,
):
    """List recent crash reports for the current user."""
    _attach_refreshed_token(user, response)

    cursor = get_db().crash_logs.find(
        {"user_id": user["_id"]},
        sort=[("received_at", -1)],
    ).limit(min(limit, 200))

    results = []
    async for doc in cursor:
        doc.pop("_id", None)
        doc.pop("user_id", None)
        results.append(doc)
    return results


def _attach_refreshed_token(user: dict, response: Response | None) -> None:
    payload = user.get("_token_payload")
    if payload and response:
        new_token = maybe_refresh_token(payload)
        if new_token:
            response.headers["X-Refreshed-Token"] = new_token
