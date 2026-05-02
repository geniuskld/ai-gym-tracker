"""One-shot backfill: add `body_part` to every exercise log entry that
lacks it.

Existing strength workout_logs may have been ingested before the body_part
denorm middleware was deployed. This script walks the collection, resolves
body_part the same way the live POST /log handler does (catalog_id first,
then plans-collection fallback), and writes the field in place.

Idempotent: re-running over already-backfilled logs is a no-op.

Usage:
    # inside container
    python -m tools.backfill_log_body_parts
    # locally with port-forwarded mongo
    MONGODB_URL=mongodb://localhost:27017 \\
      python -m tools.backfill_log_body_parts
"""

import asyncio
import logging
import os
from typing import Any

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

logger = logging.getLogger("backfill_body_part")


async def _resolve_body_part(
    db: AsyncIOMotorDatabase,
    user_id: Any,
    plan_id: str | None,
    plan_version: int | None,
    exercise_id: str | None,
    catalog_id: str | None,
    plan_cache: dict[tuple, dict[str, str]],
) -> str | None:
    """Same resolution as live middleware: catalog first, plan fallback."""
    if catalog_id:
        cat = await db.exercises.find_one(
            {"slug": catalog_id},
            projection={"body_part": 1, "_id": 0},
        )
        if cat and cat.get("body_part"):
            return cat["body_part"]

    if plan_id is None or plan_version is None or exercise_id is None:
        return None

    cache_key = (user_id, plan_id, plan_version)
    if cache_key not in plan_cache:
        plan_doc = await db.plans.find_one(
            {"user_id": user_id, "plan_id": plan_id, "plan_version": plan_version},
            projection={"templates": 1, "_id": 0},
        )
        ex_map: dict[str, str] = {}
        if plan_doc:
            for tmpl in plan_doc.get("templates", []) or []:
                for grp in tmpl.get("groups", []) or []:
                    for ex in grp.get("exercises", []) or []:
                        ex_id = ex.get("id")
                        bp = ex.get("body_part")
                        if ex_id and bp:
                            ex_map[ex_id] = bp
        plan_cache[cache_key] = ex_map

    return plan_cache[cache_key].get(exercise_id)


async def backfill(db: AsyncIOMotorDatabase) -> dict[str, int]:
    """Walk strength workout_logs and fill missing `body_part` per exercise."""
    plan_cache: dict[tuple, dict[str, str]] = {}
    scanned = 0
    updated = 0
    exercises_filled = 0

    cursor = db.workout_logs.find({"plan_type": "strength"})
    async for doc in cursor:
        scanned += 1
        exercises = doc.get("exercises") or []
        if not exercises:
            continue

        changed = False
        for ex in exercises:
            if not isinstance(ex, dict):
                continue
            if ex.get("body_part"):
                continue
            bp = await _resolve_body_part(
                db,
                user_id=doc.get("user_id"),
                plan_id=doc.get("plan_id"),
                plan_version=doc.get("plan_version"),
                exercise_id=ex.get("exercise_id"),
                catalog_id=ex.get("catalog_id"),
                plan_cache=plan_cache,
            )
            if bp:
                ex["body_part"] = bp
                exercises_filled += 1
                changed = True

        if changed:
            await db.workout_logs.update_one(
                {"_id": doc["_id"]},
                {"$set": {"exercises": exercises}},
            )
            updated += 1

    summary = {
        "scanned": scanned,
        "logs_updated": updated,
        "exercise_entries_filled": exercises_filled,
    }
    logger.info("backfill done: %s", summary)
    return summary


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)

    async def _main() -> None:
        url = os.environ.get("MONGODB_URL", "mongodb://localhost:27017")
        db_name = os.environ.get("MONGODB_DB", "ironlog")
        client = AsyncIOMotorClient(url)
        try:
            summary = await backfill(client[db_name])
            print(summary)
        finally:
            client.close()

    asyncio.run(_main())
