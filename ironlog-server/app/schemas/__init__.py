from enum import Enum

from app.schemas import strength_v1

SCHEMA_REGISTRY: dict[str, object] = {
    "strength": strength_v1,
}

PlanType = Enum("PlanType", {k: k for k in SCHEMA_REGISTRY})
