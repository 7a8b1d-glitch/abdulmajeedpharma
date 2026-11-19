"""Pydantic schemas for Drug (placeholder scaffold for Phase 02)."""

from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class DrugBase(BaseModel):
    name: str
    arabic_name: Optional[str] = None
    generic_name: Optional[str] = None
    manufacturer: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    available: bool = False


class DrugCreate(DrugBase):
    pass


class DrugUpdate(DrugBase):
    name: Optional[str] = None


class DrugRead(DrugBase):
    id: str
    image_url: Optional[str] = None
    created_at: datetime

    model_config = {"from_attributes": True}
