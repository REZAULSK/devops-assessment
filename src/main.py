from contextlib import asynccontextmanager

from fastapi import FastAPI

from src.core.init_db import create_db_and_tables
from src.modules.health.api import router as health_router
from src.modules.hero.api import router as hero_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_db_and_tables()
    yield


app = FastAPI(lifespan=lifespan)

app.include_router(health_router)
app.include_router(hero_router)
