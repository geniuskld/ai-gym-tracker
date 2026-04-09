from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database import connect, close
from app.middleware import RequestIdMiddleware, AccessLogMiddleware
from app.routes.auth_routes import router as auth_router
from app.routes.schema import router as schema_router
from app.routes.plan import router as plan_router
from app.routes.log import router as log_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await connect()
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


@app.get("/health")
async def health():
    return {"status": "ok"}
