from pydantic import BaseModel, Field, EmailStr
from typing import Optional
from datetime import datetime

# Legacy mobile-based models
class UserRegistration(BaseModel):
    name: str
    mobile: str
    role: str # 'public' or 'driver'
    password: str

class UserLogin(BaseModel):
    mobile: str
    password: str

# New email-based OTP models
class RegisterInitiate(BaseModel):
    email: EmailStr
    password: str
    name: str
    role: str  # 'public' or 'driver'

class VerifyOTP(BaseModel):
    pending_user_id: str
    otp_code: str

class LoginEmail(BaseModel):
    email: EmailStr
    password: str

class MigrateToEmail(BaseModel):
    old_mobile: str
    email: EmailStr
    new_password: str

class ResendOTP(BaseModel):
    pending_user_id: str

# Database models (for MongoDB documents)
class PendingUser(BaseModel):
    email: str
    name: str
    password_hash: str  # bcrypt hashed
    role: str
    otp_code: str
    otp_created_at: datetime
    attempt_count: int = 0
    resend_count: int = 0
    resend_window_start: Optional[datetime] = None

class LocationUpdate(BaseModel):
    latitude: float
    longitude: float

class EmergencyStatus(BaseModel):
    active: bool
