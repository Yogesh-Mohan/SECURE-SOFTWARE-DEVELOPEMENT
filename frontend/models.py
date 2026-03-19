from pydantic import BaseModel, Field
from typing import Optional

class UserRegistration(BaseModel):
    name: str
    mobile: str
    role: str # 'public' or 'driver'
    password: str

class UserLogin(BaseModel):
    mobile: str
    password: str

class LocationUpdate(BaseModel):
    latitude: float
    longitude: float

class EmergencyStatus(BaseModel):
    active: bool
