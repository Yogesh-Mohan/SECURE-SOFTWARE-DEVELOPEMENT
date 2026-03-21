import os
from datetime import datetime, timedelta
from typing import Optional
from pathlib import Path
import jwt
import bcrypt
import random
import string
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from dotenv import load_dotenv
from pydantic import BaseModel
from fastapi import HTTPException, Depends, status
from fastapi.security import OAuth2PasswordBearer
from bson import ObjectId

SECRET_KEY = os.getenv("SECRET_KEY", "your-super-secret-key-1234567890")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 1 week

# Email Configuration
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587

# Load backend/.env even when the process is started from a different cwd.
_AUTH_DIR = Path(__file__).resolve().parent
load_dotenv(_AUTH_DIR / ".env")


def _get_email_config() -> tuple[str, str]:
    """Read sender credentials at call time so runtime .env updates are picked up."""
    load_dotenv(_AUTH_DIR / ".env", override=True)
    sender_email = os.getenv("SENDER_EMAIL", "").strip()
    sender_password = os.getenv("SENDER_PASSWORD", "").strip()
    return sender_email, sender_password


def _looks_like_placeholder(value: str) -> bool:
    value_lower = value.strip().lower()
    if not value_lower:
        return True
    placeholder_tokens = ("your-", "example", "xxxx")
    return any(token in value_lower for token in placeholder_tokens)

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

def generate_otp() -> str:
    """Generate a 6-digit OTP code"""
    return ''.join(random.choices(string.digits, k=6))

def send_otp_email(to_email: str, otp_code: str) -> bool:
    """
    Send OTP to email via Gmail SMTP
    Returns True if successful, False otherwise
    """
    try:
        sender_email, sender_password = _get_email_config()

        # Fail fast when env vars are not configured.
        if (
            not sender_email
            or not sender_password
            or _looks_like_placeholder(sender_email)
            or _looks_like_placeholder(sender_password)
        ):
            print("Error sending OTP email: SENDER_EMAIL/SENDER_PASSWORD not configured")
            return False

        # Create email message
        msg = MIMEMultipart("alternative")
        msg["Subject"] = "Your Emergency Tracking OTP Code"
        msg["From"] = sender_email
        msg["To"] = to_email
        
        # HTML email body
        html_body = f"""
        <html>
            <body style="font-family: Arial, sans-serif;">
                <div style="max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f5f5f5;">
                    <div style="background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
                        <h2 style="color: #e74c3c; margin-bottom: 20px;">LIFE-TRACK Emergency Services</h2>
                        <p style="color: #333; font-size: 16px;">Hello,</p>
                        <p style="color: #333; font-size: 16px;">Your OTP code for email verification is:</p>
                        
                        <div style="background-color: #e74c3c; color: white; padding: 20px; border-radius: 8px; text-align: center; margin: 30px 0;">
                            <p style="font-size: 32px; font-weight: bold; letter-spacing: 5px; margin: 0;">{otp_code}</p>
                        </div>
                        
                        <p style="color: #666; font-size: 14px;">
                            <strong>⚠️ Important:</strong> This code is valid for <strong>10 minutes</strong> only.
                        </p>
                        <p style="color: #666; font-size: 14px;">
                            Do not share this code with anyone. Our team will never ask for your OTP.
                        </p>
                        
                        <hr style="border: none; border-top: 1px solid #ddd; margin: 30px 0;">
                        
                        <p style="color: #999; font-size: 12px; text-align: center; margin-top: 20px;">
                            © 2026 LIFE-TRACK. All rights reserved.
                        </p>
                    </div>
                </div>
            </body>
        </html>
        """
        
        # Plain text fallback
        text_body = f"""
        LIFE-TRACK Emergency Services
        
        Your OTP code for email verification: {otp_code}
        
        This code is valid for 10 minutes only.
        Do not share this code with anyone.
        
        © 2026 LIFE-TRACK
        """
        
        msg.attach(MIMEText(text_body, "plain"))
        msg.attach(MIMEText(html_body, "html"))
        
        # Send email
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()  # Enable TLS
            server.login(sender_email, sender_password)
            server.send_message(msg)
        
        return True
    except Exception as e:
        print(f"Error sending OTP email: {e}")
        return False

def generate_verification_token() -> str:
    """Generate temporary verification token for backend tracking"""
    return ''.join(random.choices(string.ascii_uppercase + string.digits, k=16))

def _get_users_collection():
    # Import lazily to avoid circular imports at module load time.
    from .main import users_collection

    return users_collection

def _get_pending_users_collection():
    # Import lazily to avoid circular imports at module load time.
    from .main import pending_users_collection

    return pending_users_collection

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
