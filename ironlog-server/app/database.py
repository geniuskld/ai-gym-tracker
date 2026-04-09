from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase
from pymongo import IndexModel, ASCENDING, DESCENDING

from app.config import settings

client: AsyncIOMotorClient = None  # type: ignore[assignment]
_db: AsyncIOMotorDatabase = None  # type: ignore[assignment]


def get_db() -> AsyncIOMotorDatabase:
    return _db


async def connect() -> None:
    global client, _db
    client = AsyncIOMotorClient(settings.mongodb_url)
    _db = client[settings.mongodb_db]
    await _ensure_indexes()


async def close() -> None:
    if client:
        client.close()


async def _ensure_indexes() -> None:
    # users
    await _db.users.create_indexes([
        IndexModel([("email", ASCENDING)], unique=True),
    ])

    # plans
    await _db.plans.create_indexes([
        IndexModel(
            [
                ("user_id", ASCENDING),
                ("plan_type", ASCENDING),
                ("plan_id", ASCENDING),
                ("plan_version", ASCENDING),
            ],
            unique=True,
        ),
        IndexModel(
            [
                ("user_id", ASCENDING),
                ("plan_type", ASCENDING),
                ("plan_id", ASCENDING),
                ("plan_version", DESCENDING),
            ],
        ),
    ])

    # workout_logs
    await _db.workout_logs.create_indexes([
        IndexModel(
            [("user_id", ASCENDING), ("id", ASCENDING)],
            unique=True,
        ),
        IndexModel([("user_id", ASCENDING), ("started_at", DESCENDING)]),
        IndexModel([("user_id", ASCENDING), ("template_id", ASCENDING)]),
    ])
