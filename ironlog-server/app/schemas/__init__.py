from app.schemas import strength_v1

SCHEMA_REGISTRY: dict[str, dict] = {
    "strength": {
        "current_version": "1.0",
        "versions": {
            "1.0": strength_v1,
        },
    },
}


def supported_types_summary() -> dict:
    return {
        name: {"current_version": info["current_version"]}
        for name, info in SCHEMA_REGISTRY.items()
    }
