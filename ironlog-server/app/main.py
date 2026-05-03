from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database import connect, close, get_db
from app.middleware import RequestIdMiddleware, AccessLogMiddleware
from app.routes.auth_routes import router as auth_router
from app.routes.schema import router as schema_router
from app.routes.plan import router as plan_router
from app.routes.log import router as log_router
from app.routes.crash import router as crash_router
from app.routes.catalog import router as catalog_router
from app.routes.analytics import router as analytics_router
from app.routes.agent_instructions import router as agent_instructions_router
from app.routes.exercise_docs import router as exercise_docs_router
from tools.bootstrap_catalog import bootstrap as bootstrap_catalog


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect()
    # Idempotent seed of the exercise/muscle catalog from JSON. Safe to
    # run on every startup -- existing entries are upserted by `slug`.
    try:
        await bootstrap_catalog(get_db())
    except Exception as e:
        # Don't crash the app if the seed files are temporarily broken --
        # the API can still serve everything else.
        import logging
        logging.getLogger("startup").warning("catalog bootstrap failed: %s", e)
    yield
    await close()


app = FastAPI(
    title="IronLog Sync Server",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(AccessLogMiddleware)
app.add_middleware(RequestIdMiddleware)

app.include_router(auth_router)
app.include_router(schema_router)
app.include_router(plan_router)
app.include_router(log_router)
app.include_router(crash_router)
app.include_router(catalog_router)
app.include_router(exercise_docs_router)
app.include_router(analytics_router)
app.include_router(agent_instructions_router)


@app.get("/health")
async def health():
    return {"status": "ok"}
