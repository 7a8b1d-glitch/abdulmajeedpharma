"""Abdulmajeedpharma (APH) — FastAPI backend entry point."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.api import api_router

app = FastAPI(
    title="Abdulmajeedpharma API",
    description="Pharmaceutical platform backend for Abdulmajeedpharma (APH).",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api/v1")


@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok", "service": "aph-backend"}


@app.get("/", tags=["root"])
async def root():
    return {
        "app": "Abdulmajeedpharma",
        "short_name": "APH",
        "owner": "Dr. Abdulmajeed Abdullah Almakhedhi",
        "version": "0.1.0",
        "phase": "Phase 01 — Foundation",
    }
