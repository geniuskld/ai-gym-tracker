import json
import time
import uuid
from datetime import datetime, timezone

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response


class RequestIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        request_id = request.headers.get("X-Request-Id") or str(uuid.uuid4())
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        return response


class AccessLogMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        start = time.monotonic()
        response = await call_next(request)
        elapsed_ms = round((time.monotonic() - start) * 1000, 1)

        log_entry = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "method": request.method,
            "path": request.url.path,
            "status": response.status_code,
            "ms": elapsed_ms,
            "request_id": getattr(request.state, "request_id", None),
            "ip": request.client.host if request.client else None,
        }
        print(json.dumps(log_entry, ensure_ascii=False))
        return response
