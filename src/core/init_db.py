import asyncio
import logging

from sqlalchemy.exc import SQLAlchemyError

from src.core.db import Base, engine

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 10
MAX_DELAY_SECONDS = 15.0


async def create_db_and_tables(
    max_attempts: int = MAX_ATTEMPTS, base_delay: float = 1.0
) -> None:
    """Create the schema, retrying while the database is still coming up.

    Startup ordering is not guaranteed anywhere this runs. Locally, Compose can
    start the API before Postgres finishes booting; on ECS there is no ordering
    primitive at all, and a task replacement during an RDS failover will find
    the endpoint briefly unreachable.

    Without a retry, each of those becomes a crashed task, which ECS replaces
    with another task that crashes the same way — an outage that outlives its
    cause. Backing off instead absorbs a slow start of up to roughly two
    minutes.

    The retry is bounded on purpose. A wrong password or an unreachable subnet
    will never resolve itself, and a task that fails loudly is easier to
    diagnose than one that retries silently forever.
    """
    delay = base_delay

    for attempt in range(1, max_attempts + 1):
        try:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
        except (SQLAlchemyError, OSError) as exc:
            if attempt == max_attempts:
                logger.error(
                    "database unreachable after %s attempts; giving up",
                    max_attempts,
                    extra={"event": "db.init.failed"},
                )
                raise

            logger.warning(
                "database not ready (attempt %s/%s): %s; retrying in %.1fs",
                attempt,
                max_attempts,
                exc.__class__.__name__,
                delay,
                extra={"event": "db.init.retry"},
            )
            await asyncio.sleep(delay)
            delay = min(delay * 2, MAX_DELAY_SECONDS)
        else:
            logger.info(
                "database schema ready",
                extra={"event": "db.init.ok", "otel_attempts": attempt},
            )
            return
