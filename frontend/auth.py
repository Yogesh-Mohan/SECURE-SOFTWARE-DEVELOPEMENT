import os
from datetime import datetime, timedelta
from typing import Optional
import jwt
import bcrypt
from pydantic import BaseModel
from fastapi import HTTPException, Depends, status
from fastapi.security import OAuth2PasswordBearer
from bson import ObjectId

SECRET_KEY = os.getenv("SECRET_KEY", "your-super-secret-key-1234567890")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 1 week

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

class TokenData(BaseModel):
    user_id: str
    role: str

def verify_password(plain_password, hashed_password):
    try:
        return bcrypt.checkpw(plain_password.encode(), hashed_password.encode())
    except Exception:
        return False

def get_password_hash(password):
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def _get_users_collection():
    # Import lazily to avoid circular imports at module load time.
    from .main import users_collection

    return users_collection

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("user_id")
        if user_id is None:
            raise credentials_exception
        TokenData(user_id=user_id, role=payload.get("role", "public"))
    except jwt.PyJWTError:
        raise credentials_exception

    users_collection = _get_users_collection()
    if users_collection is None:
        raise credentials_exception

    try:
        user = users_collection.find_one({"_id": ObjectId(user_id)})
    except Exception:
        raise credentials_exception

    if user is None:
        raise credentials_exception

    return user
