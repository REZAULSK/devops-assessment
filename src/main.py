import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.core.init_db import create_db_and_tables
from src.core.logging import configure_logging
from src.core.telemetry import setup_telemetry
from src.modules.health.api import router as health_router
from src.modules.hero.api import router as hero_router

# Logging is configured before anything else so that startup failures are
# themselves emitted as structured JSON rather than as a bare traceback.
configure_logging(os.getenv("LOG_LEVEL", "INFO"))

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_db_and_tables()
    logger.info("application startup complete", extra={"event": "startup"})
    yield
    logger.info("application shutdown", extra={"event": "shutdown"})


app = FastAPI(lifespan=lifespan)

setup_telemetry(app)

app.include_router(health_router)
app.include_router(hero_router)
