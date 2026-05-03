"""Idempotently seed the exercise catalog from JSON files.

Reads `tools/seed_data/muscle_groups.json` and `tools/seed_data/exercises.json`
and upserts each entry by `slug` into the corresponding mongo collection.
Safe to run on every container start -- existing entries are updated in
place; new entries are inserted.

Usage (inside container):
    python -m tools.bootstrap_catalog
Or programmatically from app startup -- see `app/main.py` lifespan.
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from motor.motor_asyncio import AsyncIOMotorDatabase

logger = logging.getLogger("bootstrap_catalog")

_THIS_DIR = Path(__file__).parent
SEED_MUSCLES = _THIS_DIR / "seed_data" / "muscle_groups.json"
SEED_EXERCISES = _THIS_DIR / "seed_data" / "exercises.json"
SEED_EXERCISE_DOCS_RU = _THIS_DIR / "seed_data" / "exercise_docs.ru.json"


def _load(path: Path) -> list[dict[str, Any]]:
    return json.loads(path.read_text(encoding="utf-8"))


async def _upsert_many(
    collection,
    docs: list[dict[str, Any]],
    label: str,
) -> tuple[int, int]:
    """Upserts each doc by `slug`. Returns (inserted_count, updated_count)."""
    now = datetime.now(timezone.utc)
    inserted = 0
    updated = 0

    for doc in docs:
        slug = doc["slug"]
        existing = await collection.find_one({"slug": slug})
        doc["updated_at"] = now
        if existing is None:
            doc["created_at"] = now
            # `deprecated` defaults to False if not specified in seed.
            doc.setdefault("deprecated", False)
            doc.setdefault("replaced_by", None)
            await collection.insert_one(doc)
            inserted += 1
        else:
            # Preserve created_at + deprecated/replaced_by from existing doc
            # so manual edits (e.g. via PATCH /exercises/{slug}/deprecate)
            # are not wiped on container restart.
            doc["created_at"] = existing.get("created_at", now)
            doc["deprecated"] = existing.get("deprecated", False)
            doc["replaced_by"] = existing.get("replaced_by", None)
            await collection.replace_one({"slug": slug}, doc)
            updated += 1

    logger.info(
        "Bootstrapped %s: %d inserted, %d updated", label, inserted, updated
    )
    return inserted, updated


async def _insert_missing_exercise_docs(
    collection,
    docs: list[dict[str, Any]],
) -> tuple[int, int]:
    """Insert exercise docs by (exercise_slug, locale), preserving DB edits."""
    now = datetime.now(timezone.utc)
    inserted = 0
    skipped = 0

    for doc in docs:
        query = {
            "exercise_slug": doc["exercise_slug"],
            "locale": doc.get("locale", "ru"),
        }
        existing = await collection.find_one(query, projection={"_id": 1})
        if existing:
            skipped += 1
            continue

        doc = dict(doc)
        doc.setdefault("content_version", 1)
        doc.setdefault("status", "draft")
        doc["created_at"] = now
        doc["updated_at"] = now
        await collection.insert_one(doc)
        inserted += 1

    logger.info(
        "Bootstrapped exercise_docs: %d inserted, %d skipped", inserted, skipped
    )
    return inserted, skipped


async def bootstrap(db: AsyncIOMotorDatabase) -> None:
    """Run muscle_groups + exercises seed against the given mongo DB."""
    muscles = _load(SEED_MUSCLES)
    exercises = _load(SEED_EXERCISES)

    await _upsert_many(db.muscle_groups, muscles, "muscle_groups")
    await _upsert_many(db.exercises, exercises, "exercises")
    if SEED_EXERCISE_DOCS_RU.exists():
        await _insert_missing_exercise_docs(
            db.exercise_docs,
            _load(SEED_EXERCISE_DOCS_RU),
        )


# Allow `python -m tools.bootstrap_catalog` for ad-hoc invocation.
if __name__ == "__main__":
    import os
    from motor.motor_asyncio import AsyncIOMotorClient

    logging.basicConfig(level=logging.INFO)

    async def _main() -> None:
        url = os.environ.get("MONGODB_URL", "mongodb://localhost:27017")
        db_name = os.environ.get("MONGODB_DB", "ironlog")
        client = AsyncIOMotorClient(url)
        try:
            await bootstrap(client[db_name])
        finally:
            client.close()

    asyncio.run(_main())
