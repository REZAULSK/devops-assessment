from fastapi import APIRouter, Depends, Response, status
from opentelemetry.instrumentation.utils import suppress_instrumentation
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.core.db import get_session

router = APIRouter(tags=["Health"])


@router.get("/health")
async def health() -> dict[str, str]:
    """Liveness probe.

    Answers one question only: is this process alive and able to serve HTTP?
    It deliberately touches no dependencies, so a slow or briefly unavailable
    database can never cause the load balancer to kill otherwise healthy tasks.
    """
    return {"status": "ok"}


@router.get("/ready")
async def ready(
    response: Response,
    session: AsyncSession = Depends(get_session),
) -> dict[str, str]:
    """Readiness probe.

    Answers a stricter question: can this instance actually do useful work?
    Used by humans and deployment checks, not by the load balancer.

    Instrumentation is suppressed around the probe query. Excluding this route
    from the HTTP instrumentation removes the server span but not the SQLAlchemy
    span nested inside it — and a database span with no parent is promoted to a
    root trace of its own. Probes would therefore appear in X-Ray as a steady
    drip of one-span traces: noise in the service map, and billed per trace.
    """
    try:
        with suppress_instrumentation():
            await session.execute(text("SELECT 1"))
    except Exception:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "degraded", "database": "unreachable"}

    return {"status": "ok", "database": "ok"}
