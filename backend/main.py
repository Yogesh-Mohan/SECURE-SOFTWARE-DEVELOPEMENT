from fastapi import FastAPI, HTTPException, status, Header
from fastapi.middleware.cors import CORSMiddleware
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure
from bson import ObjectId
from pydantic import BaseModel, Field, ConfigDict, ValidationError
from typing import Any, List, Optional
import os
import logging
import asyncio
import math
import jwt
import json
import time
import urllib.parse
import urllib.request
import urllib.error
import bcrypt
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

# JWT configuration
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
ALERT_RADIUS_METERS = float(os.getenv("ALERT_RADIUS_METERS", "300"))
ALERT_SCAN_INTERVAL_SECONDS = int(os.getenv("ALERT_SCAN_INTERVAL_SECONDS", "5"))
ALERT_DEDUPE_SECONDS = int(os.getenv("ALERT_DEDUPE_SECONDS", "60"))
FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID", "")
REQUIRE_NOTIFY_AUTH = os.getenv("REQUIRE_NOTIFY_AUTH", "false").lower() in ("1", "true", "yes")

alert_worker_task: Optional[asyncio.Task] = None

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Ambulance Backend API",
    description="Backend server for ambulance service",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# MongoDB connection configuration
MONGO_URL = os.getenv("MONGO_URL", "mongodb://localhost:27017")
DATABASE_NAME = os.getenv("DATABASE_NAME", "admin")

# Initialize collections as None
users_collection = None
ambulance_collection = None
alerts_collection = None

try:
    client = MongoClient(MONGO_URL, serverSelectionTimeoutMS=5000)
    # Verify connection
    client.admin.command('ping')
    db = client[DATABASE_NAME]
    
    # Create collection references
    users_collection = db["users"]
    ambulance_collection = db["ambulance"]
    alerts_collection = db["alerts"]
    
    logger.info("✓ Connected to MongoDB successfully")
except (ServerSelectionTimeoutError, OperationFailure) as e:
    logger.error(f"✗ MongoDB connection failed: {e}")
    raise RuntimeError(f"Failed to connect to MongoDB at {MONGO_URL}")


# Pydantic models for request/response
class Location(BaseModel):
    lat: float = Field(..., description="Latitude coordinate")
    lng: float = Field(..., description="Longitude coordinate")
    model_config = ConfigDict(json_schema_extra={"example": {"lat": 0.0, "lng": 0.0}})


class User(BaseModel):
    name: str = Field(..., min_length=1, max_length=255, description="User name")
    role: str = Field(..., min_length=1, max_length=50, description="User role")
    mobile: Optional[str] = Field(default=None, min_length=10, max_length=15, description="User mobile number")
    password: Optional[str] = Field(default=None, min_length=6, description="Optional password for auth")
    location: Location = Field(default_factory=lambda: Location(lat=0, lng=0), description="User location")
    model_config = ConfigDict(json_schema_extra={
        "example": {
            "name": "John Doe",
            "mobile": "9876543210",
            "role": "public",
            "password": "secret123",
            "location": {"lat": 12.9716, "lng": 77.5946}
        }
    })


class ErrorResponse(BaseModel):
    detail: str
    status_code: int


class UserAddResponse(BaseModel):
    message: str
    user_id: str
    user: dict
    model_config = ConfigDict(json_schema_extra={
        "example": {
            "message": "User added successfully",
            "user_id": "507f1f77bcf86cd799439011",
            "user": {
                "name": "test user",
                "role": "public",
                "location": {"lat": 0, "lng": 0}
            }
        }
    })


class UsersListResponse(BaseModel):
    total: int
    users: List[dict]
    model_config = ConfigDict(json_schema_extra={
        "example": {
            "total": 1,
            "users": [
                {
                    "_id": "507f1f77bcf86cd799439011",
                    "name": "test user",
                    "role": "public",
                    "location": {"lat": 0, "lng": 0}
                }
            ]
        }
    })


# Auth models
class RegisterRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    mobile: str = Field(..., min_length=10, max_length=15)
    role: str = Field(..., description="Role: 'public', 'driver', or 'admin'")
    password: str = Field(..., min_length=6)


class LoginRequest(BaseModel):
    mobile: str = Field(..., min_length=10)
    password: str = Field(...)


class LocationUpdate(BaseModel):
    latitude: float
    longitude: float


class EmergencyStatus(BaseModel):
    active: bool


class NearbyUserNotification(BaseModel):
    user_id: str = Field(..., min_length=1)
    fcm_token: str = Field(..., min_length=1)


class NotifyNearbyRequest(BaseModel):
    nearby_users: List[NearbyUserNotification] = Field(default_factory=list)
    message: str = Field(default="🚨 Ambulance coming – move left")


class AuthResponse(BaseModel):
    access_token: str
    user_id: str
    name: str
    role: str
    message: str


class AuthResponse(BaseModel):
    access_token: str
    user_id: str
    name: str
    role: str
    message: str


# Utility functions
def hash_password(password: str) -> str:
    """Hash password using bcrypt"""
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(password: str, hashed: str) -> bool:
    """Verify password against hash"""
    return bcrypt.checkpw(password.encode(), hashed.encode())


def create_access_token(data: dict):
    """Create JWT access token"""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def verify_token(token: str):
    """Verify JWT token"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        if user_id is None:
            raise HTTPException(status_code=401, detail="Invalid token")
        return user_id
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


def _extract_lat_lng(doc: dict) -> Optional[tuple]:
    """Normalize location coordinates from nested or flat schema."""
    location = doc.get("location")
    if isinstance(location, dict):
        lat = location.get("lat")
        lng = location.get("lng")
        if lat is not None and lng is not None:
            return float(lat), float(lng)

    lat = doc.get("latitude")
    lng = doc.get("longitude")
    if lat is not None and lng is not None:
        return float(lat), float(lng)

    return None


def haversine_distance_meters(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate distance between two geo points in meters."""
    radius = 6371000
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lng2 - lng1)

    a = math.sin(d_phi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return radius * c


def trigger_alert_placeholder(user_doc: dict, message: str) -> None:
    """Notification placeholder. Replace with push/SMS integration later."""
    logger.info("Alert triggered for user=%s message=%s", user_doc.get("_id"), message)


def _load_firebase_service_account() -> dict:
    """Load Firebase service account from env JSON or env file path."""
    raw_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    json_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_FILE")

    if raw_json:
        data = json.loads(raw_json)
    elif json_path:
        with open(json_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    else:
        raise RuntimeError(
            "Missing Firebase credentials. Set FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT_FILE"
        )

    private_key = data.get("private_key", "")
    if isinstance(private_key, str):
        data["private_key"] = private_key.replace("\\n", "\n")

    return data


def _fetch_google_access_token(service_account: dict) -> str:
    """Create OAuth2 access token for Firebase Cloud Messaging HTTP v1."""
    now = int(time.time())
    token_uri = service_account.get("token_uri", "https://oauth2.googleapis.com/token")
    claims = {
        "iss": service_account["client_email"],
        "scope": "https://www.googleapis.com/auth/firebase.messaging",
        "aud": token_uri,
        "iat": now,
        "exp": now + 3600,
    }

    assertion = jwt.encode(
        claims,
        service_account["private_key"],
        algorithm="RS256",
    )

    body = urllib.parse.urlencode(
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }
    ).encode("utf-8")

    req = urllib.request.Request(
        token_uri,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=15) as resp:
        payload = json.loads(resp.read().decode("utf-8"))

    access_token = payload.get("access_token")
    if not access_token:
        raise RuntimeError("Unable to obtain Google access token")
    return access_token


def _send_fcm_notification(
    *,
    fcm_token: str,
    message: str,
    project_id: str,
    access_token: str,
) -> tuple[bool, str]:
    """Send one FCM notification via HTTP v1."""
    endpoint = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
    payload = {
        "message": {
            "token": fcm_token,
            "notification": {
                "title": "Emergency Alert",
                "body": message,
            },
            "android": {
                "priority": "high",
            },
        }
    }

    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {access_token}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            if 200 <= resp.status < 300:
                return True, "ok"
            return False, f"HTTP {resp.status}"
    except urllib.error.HTTPError as ex:
        try:
            reason = ex.read().decode("utf-8")
        except Exception:
            reason = str(ex)
        return False, reason
    except Exception as ex:
        return False, str(ex)


def run_ambulance_priority_cycle() -> dict:
    """Run one cycle: detect nearby users and store alerts."""
    if users_collection is None or ambulance_collection is None or alerts_collection is None:
        raise RuntimeError("Database collections not initialized")

    cycle_time = datetime.utcnow()
    total_alerts = 0
    active_ambulances = 0

    users = list(users_collection.find({}, {"location": 1, "latitude": 1, "longitude": 1}))

    for ambulance in ambulance_collection.find({}):
        if not ambulance.get("is_active", False):
            continue

        ambulance_location = _extract_lat_lng(ambulance)
        if ambulance_location is None:
            continue

        active_ambulances += 1
        ambulance_lat, ambulance_lng = ambulance_location

        for user in users:
            user_location = _extract_lat_lng(user)
            if user_location is None:
                continue

            user_lat, user_lng = user_location
            distance_meters = haversine_distance_meters(ambulance_lat, ambulance_lng, user_lat, user_lng)
            if distance_meters > ALERT_RADIUS_METERS:
                continue

            message = "Ambulance coming - move left/right"
            trigger_alert_placeholder(user, message)

            alerts_collection.insert_one(
                {
                    "user_id": str(user.get("_id")),
                    "ambulance_id": str(ambulance.get("_id")),
                    "message": message,
                    "timestamp": cycle_time,
                    "distance_meters": round(distance_meters, 2),
                }
            )
            total_alerts += 1

    return {
        "active_ambulances": active_ambulances,
        "alerts_created": total_alerts,
        "radius_meters": ALERT_RADIUS_METERS,
        "timestamp": cycle_time,
    }


async def ambulance_priority_worker() -> None:
    """Background loop to evaluate ambulance proximity continuously."""
    while True:
        try:
            result = run_ambulance_priority_cycle()
            if result["alerts_created"]:
                logger.info(
                    "Priority cycle complete: active_ambulances=%s alerts_created=%s",
                    result["active_ambulances"],
                    result["alerts_created"],
                )
        except Exception as ex:
            logger.exception("Ambulance priority cycle failed: %s", ex)

        await asyncio.sleep(ALERT_SCAN_INTERVAL_SECONDS)


@app.on_event("startup")
async def start_ambulance_priority_worker() -> None:
    global alert_worker_task
    if alert_worker_task is None:
        alert_worker_task = asyncio.create_task(ambulance_priority_worker())
        logger.info(
            "Ambulance priority worker started (interval=%ss radius=%sm)",
            ALERT_SCAN_INTERVAL_SECONDS,
            ALERT_RADIUS_METERS,
        )


@app.on_event("shutdown")
async def stop_ambulance_priority_worker() -> None:
    global alert_worker_task
    if alert_worker_task is not None:
        alert_worker_task.cancel()
        try:
            await alert_worker_task
        except asyncio.CancelledError:
            pass
        alert_worker_task = None


# Routes
@app.get("/", response_model=dict, tags=["Health"])
def read_root():
    """Health check endpoint"""
    logger.info("Health check endpoint called")
    return {"message": "Backend working"}


@app.get("/add-user", tags=["Users"])
@app.get("/add-user/", tags=["Users"])
def add_user_get_hint():
    return {"message": "Use POST /add-user with JSON body"}


@app.get("/register", tags=["Auth"])
@app.get("/register/", tags=["Auth"])
def register_get_hint():
    return {"message": "Use POST /register with JSON body"}


@app.get("/login", tags=["Auth"])
@app.get("/login/", tags=["Auth"])
def login_get_hint():
    return {"message": "Use POST /login with JSON body"}


@app.post(
    "/add-user",
    response_model=UserAddResponse,
    status_code=status.HTTP_201_CREATED,
    responses={400: {"model": ErrorResponse}, 500: {"model": ErrorResponse}},
    tags=["Users"]
)
@app.post(
    "/add-user/",
    response_model=UserAddResponse,
    status_code=status.HTTP_201_CREATED,
    responses={400: {"model": ErrorResponse}, 500: {"model": ErrorResponse}},
    tags=["Users"]
)
def add_user(user: User):
    """
    Add a new user to the database
    
    Request body can contain:
    - name: User's name
    - role: User's role
    - mobile/password: Optional auth fields
    - location: Optional geographic location (defaults to {lat:0, lng:0})
    """
    if users_collection is None:
        logger.error("Users collection not initialized")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection failed"
        )
    
    try:
        user_dict = user.model_dump(exclude_none=True)

        if user_dict.get("mobile"):
            existing = users_collection.find_one({"mobile": user_dict["mobile"]})
            if existing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Mobile number already registered"
                )

        if user_dict.get("password"):
            user_dict["password"] = hash_password(user_dict["password"])

        user_dict["created_at"] = datetime.utcnow()

        result = users_collection.insert_one(user_dict)
        logger.info(f"User added with ID: {result.inserted_id}")
        
        # Convert ObjectId to string for serialization
        user_response = user_dict.copy()
        user_response.pop("password", None)
        
        return {
            "message": "User added successfully",
            "user_id": str(result.inserted_id),
            "user": user_response
        }
    except ValidationError as e:
        logger.warning(f"Validation error: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid user data: {str(e)}"
        )
    except OperationFailure as e:
        logger.error(f"MongoDB operation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to insert user into database"
        )
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred"
        )


@app.get(
    "/get-users",
    response_model=UsersListResponse,
    responses={500: {"model": ErrorResponse}},
    tags=["Users"]
)
def get_users():
    """Retrieve all users from the database"""
    if users_collection is None:
        logger.error("Users collection not initialized")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection failed"
        )
    
    try:
        users = []
        for user in users_collection.find():
            user["_id"] = str(user["_id"])  # Convert ObjectId to string
            users.append(user)
        
        logger.info(f"Retrieved {len(users)} users from database")
        
        return {
            "total": len(users),
            "users": users
        }
    except OperationFailure as e:
        logger.error(f"MongoDB operation failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve users from database"
        )
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred"
        )


# Authentication endpoints
@app.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED, tags=["Auth"])
@app.post("/register/", response_model=AuthResponse, status_code=status.HTTP_201_CREATED, tags=["Auth"])
def register(request: RegisterRequest):
    """Register a new user"""
    if users_collection is None:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    try:
        # Check if user already exists
        existing = users_collection.find_one({"mobile": request.mobile})
        if existing:
            raise HTTPException(status_code=400, detail="Mobile number already registered")
        
        # Create user document
        user_doc = {
            "name": request.name,
            "mobile": request.mobile,
            "role": request.role,
            "password": hash_password(request.password),
            "created_at": datetime.utcnow(),
            "location": {"lat": 0, "lng": 0}
        }
        
        result = users_collection.insert_one(user_doc)
        user_id = str(result.inserted_id)
        
        # Create token
        token = create_access_token(data={"sub": user_id})
        
        logger.info(f"User registered: {user_id}")
        
        return {
            "access_token": token,
            "user_id": user_id,
            "name": request.name,
            "role": request.role,
            "message": "Registration successful"
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Registration error: {e}")
        raise HTTPException(status_code=500, detail="Registration failed")


@app.post("/login", response_model=AuthResponse, tags=["Auth"])
@app.post("/login/", response_model=AuthResponse, tags=["Auth"])
def login(request: LoginRequest):
    """Login with mobile and password"""
    if users_collection is None:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    try:
        # Find user
        user = users_collection.find_one({"mobile": request.mobile})
        if not user:
            raise HTTPException(status_code=401, detail="Invalid mobile or password")
        
        # Verify password
        if not verify_password(request.password, user.get("password", "")):
            raise HTTPException(status_code=401, detail="Invalid mobile or password")
        
        user_id = str(user["_id"])
        # Create token
        token = create_access_token(data={"sub": user_id})
        
        logger.info(f"User logged in: {user_id}")
        
        return {
            "access_token": token,
            "user_id": user_id,
            "name": user["name"],
            "role": user["role"],
            "message": "Login successful"
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Login error: {e}")
        raise HTTPException(status_code=500, detail="Login failed")


@app.post("/update-location", tags=["Location"])
def update_location(request: LocationUpdate, authorization: Optional[str] = Header(None)):
    """Update user location"""
    if users_collection is None:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    try:
        # Extract token
        if not authorization:
            raise HTTPException(status_code=401, detail="Missing authorization header")
        
        token = authorization.replace("Bearer ", "")
        user_id = verify_token(token)
        
        # Update location
        users_collection.update_one(
            {"_id": ObjectId(user_id)},
            {"$set": {"location": {"lat": request.latitude, "lng": request.longitude}, "updated_at": datetime.utcnow()}}
        )
        
        logger.info(f"Location updated for user: {user_id}")
        
        return {"message": "Location updated successfully"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Location update error: {e}")
        raise HTTPException(status_code=500, detail="Failed to update location")


@app.post("/emergency-status", tags=["Emergency"])
def emergency_status(request: EmergencyStatus, authorization: Optional[str] = Header(None)):
    """Toggle emergency status"""
    if users_collection is None:
        raise HTTPException(status_code=500, detail="Database connection failed")
    
    try:
        # Extract token
        if not authorization:
            raise HTTPException(status_code=401, detail="Missing authorization header")
        
        token = authorization.replace("Bearer ", "")
        user_id = verify_token(token)
        
        # Update emergency status
        users_collection.update_one(
            {"_id": ObjectId(user_id)},
            {"$set": {"emergency_active": request.active, "updated_at": datetime.utcnow()}}
        )
        
        logger.info(f"Emergency status updated for user: {user_id} - Active: {request.active}")
        
        return {"message": "Emergency status updated", "active": request.active}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Emergency status error: {e}")
        raise HTTPException(status_code=500, detail="Failed to update emergency status")


@app.post("/ambulance-priority/run-once", tags=["Emergency"])
def run_priority_once() -> dict:
    """Manual trigger for one ambulance priority cycle."""
    try:
        result = run_ambulance_priority_cycle()
        result["timestamp"] = result["timestamp"].isoformat()
        return {
            "message": "Ambulance priority cycle executed",
            **result,
        }
    except Exception as ex:
        logger.error("Manual ambulance priority run failed: %s", ex)
        raise HTTPException(status_code=500, detail="Failed to run ambulance priority cycle")


@app.post("/alerts/notify-nearby", tags=["Emergency"])
def notify_nearby_users(
    request: NotifyNearbyRequest,
    authorization: Optional[str] = Header(None),
) -> dict:
    """Securely send nearby-user FCM alerts from backend and persist audit logs."""
    if alerts_collection is None:
        raise HTTPException(status_code=500, detail="Database connection failed")

    if REQUIRE_NOTIFY_AUTH:
        if users_collection is None:
            raise HTTPException(status_code=500, detail="Database connection failed")

        if not authorization:
            raise HTTPException(status_code=401, detail="Missing authorization header")

        token = authorization.replace("Bearer ", "")
        caller_user_id = verify_token(token)
        caller = users_collection.find_one({"_id": ObjectId(caller_user_id)}, {"role": 1})
        if not caller:
            raise HTTPException(status_code=401, detail="Invalid token")

        if caller.get("role") != "driver":
            raise HTTPException(status_code=403, detail="Driver role required")

    try:
        service_account = _load_firebase_service_account()
        project_id = FIREBASE_PROJECT_ID or service_account.get("project_id", "")
        if not project_id:
            raise RuntimeError("Missing Firebase project ID")

        access_token = _fetch_google_access_token(service_account)
    except Exception as ex:
        logger.error("FCM configuration error: %s", ex)
        raise HTTPException(status_code=500, detail="FCM backend is not configured")

    notified_user_ids: List[str] = []
    now = datetime.utcnow()
    dedupe_since = now - timedelta(seconds=ALERT_DEDUPE_SECONDS)

    for nearby_user in request.nearby_users:
        user_id = nearby_user.user_id.strip()
        fcm_token = nearby_user.fcm_token.strip()
        if not user_id or not fcm_token:
            continue

        existing_alert = alerts_collection.find_one(
            {
                "user_id": user_id,
                "message": request.message,
                "timestamp": {"$gte": dedupe_since},
            }
        )
        if existing_alert:
            continue

        sent, reason = _send_fcm_notification(
            fcm_token=fcm_token,
            message=request.message,
            project_id=project_id,
            access_token=access_token,
        )
        if not sent:
            logger.warning("FCM send failed for user=%s reason=%s", user_id, reason)
            continue

        alerts_collection.insert_one(
            {
                "user_id": user_id,
                "message": request.message,
                "timestamp": now,
                "source": "backend_fcm",
            }
        )
        notified_user_ids.append(user_id)

    return {
        "message": "Nearby alert processing completed",
        "requested": len(request.nearby_users),
        "notified": len(notified_user_ids),
        "notified_user_ids": notified_user_ids,
    }


# Run with: uvicorn main:app --reload
# The FastAPI app will be served at http://127.0.0.1:8000
# Swagger UI documentation: http://127.0.0.1:8000/docs
# ReDoc documentation: http://127.0.0.1:8000/redoc
