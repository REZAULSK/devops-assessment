import logging

from fastapi import HTTPException

from src.modules.hero.repository import HeroRepository
from src.modules.hero.schemas import HeroCreate

logger = logging.getLogger(__name__)


class HeroService:
    def __init__(self, repo: HeroRepository):
        self.repo = repo

    async def create(self, data: HeroCreate):
        hero = await self.repo.create(data)
        logger.info("hero created", extra={"event": "hero.created", "hero_id": hero.id})
        return hero

    async def list(self, offset: int, limit: int):
        return await self.repo.get_all(offset, limit)

    async def get(self, hero_id: int):
        hero = await self.repo.get_by_id(hero_id)
        if not hero:
            logger.warning(
                "hero not found", extra={"event": "hero.missing", "hero_id": hero_id}
            )
            raise HTTPException(status_code=404, detail="Hero not found")
        return hero

    async def delete(self, hero_id: int):
        hero = await self.repo.get_by_id(hero_id)
        if not hero:
            logger.warning(
                "hero not found", extra={"event": "hero.missing", "hero_id": hero_id}
            )
            raise HTTPException(status_code=404, detail="Hero not found")
        await self.repo.delete(hero)
        logger.info("hero deleted", extra={"event": "hero.deleted", "hero_id": hero_id})
        return {"ok": True}
