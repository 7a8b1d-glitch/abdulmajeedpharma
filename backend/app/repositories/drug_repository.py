"""Data repository for Drug domain (placeholder scaffold for Phase 02)."""

from app.models.drug import Drug


class DrugRepository:
    """Placeholder repository — real implementation in Phase 02."""

    model = Drug

    async def list(self):
        return []

    async def get(self, drug_id: str):
        return None
