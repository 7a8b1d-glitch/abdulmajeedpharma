"""Top-level API router — aggregates all versioned route modules."""

from fastapi import APIRouter

api_router = APIRouter()

# Route modules will be wired here in Phase 02:
# from app.api.v1 import drugs, auth, products, manufacturers
# api_router.include_router(drugs.router, prefix="/drugs", tags=["drugs"])


@api_router.get("/health", tags=["health"])
async def api_health():
    return {"status": "ok", "api": "v1"}
