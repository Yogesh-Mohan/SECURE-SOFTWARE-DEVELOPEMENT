from fastapi import FastAPI, HTTPException, status, Header
from fastapi.middleware.cors import CORSMiddleware
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure
from bson import ObjectId
from pydantic import BaseModel, Field, ConfigDict, ValidationError
from typing import List, Optional
import os
import logging
import jwt
import bcrypt
from pathlib import Path
from datetime import datetime, timedelta
from dotenv import load_dotenv

try:
    import firebase_admin  # type: ignore[import-not-found]
    from firebase_admin import credentials, firestore, messaging  # type: ignore[import-not-found]
except Exception:
    firebase_admin = None
    credentials = None
    firestore = None
    messaging = None

load_dotenv()

# JWT configuration
SECRET_KEY = os.getenv("cDKPAUB919U6MXroXlbS63Y81vSlIlVX", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

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
pending_users_collection = None

# Firebase Auth/OTP collections (MongoDB-independent)
firestore_db = None
otp_pending_collection = None
auth_users_collection = None

try:
    client = MongoClient(MONGO_URL, serverSelectionTimeoutMS=5000)
    # Verify connection
    client.admin.command('ping')
    db = client[DATABASE_NAME]
    
    # Create collection references
    users_collection = db["users"]
    ambulance_collection = db["ambulance"]
    alerts_collection = db["alerts"]
    pending_users_collection = db["pending_users"]
    
    logger.info("✓ Connected to MongoDB successfully")
except (ServerSelectionTimeoutError, OperationFailure) as e:
    logger.error(f"✗ MongoDB connection failed: {e}")


def _init_firestore():
    global firestore_db, otp_pending_collection, auth_users_collection
    try:
        if firebase_admin is None or credentials is None or firestore is None:
            logger.error("✗ firebase-admin package is not installed")
            return

        if not firebase_admin._apps:
            cred_env = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "").strip()
            cred_path = None

            if cred_env:
                candidate = Path(cred_env)
                if candidate.exists():
                    cred_path = candidate

            if cred_path is None:
                root_dir = Path(__file__).resolve().parent.parent
                matches = sorted(root_dir.glob("*firebase-adminsdk*.json"))
                if matches:
                    cred_path = matches[0]

            if cred_path is not None:
                firebase_admin.initialize_app(credentials.Certificate(str(cred_path)))
                logger.info(f"✓ Firebase Admin initialized using service account: {cred_path.name}")
            else:
                firebase_admin.initialize_app()
                logger.info("✓ Firebase Admin initialized using default credentials")

        firestore_db = firestore.client()
        otp_pending_collection = firestore_db.collection("otp_pending_users")
        auth_users_collection = firestore_db.collection("auth_users")
        logger.info("✓ Firestore collections initialized for OTP auth")
    except Exception as e:
        logger.error(f"✗ Firebase/Firestore initialization failed: {e}")


_init_firestore()


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
    latitude: Optional[float] = None  # Emergency location for instant alerts
    longitude: Optional[float] = None


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


def haversine_distance(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calculate distance between two coordinates in meters using Haversine formula"""
    from math import radians, cos, sin, asin, sqrt
    
    # Convert degrees to radians
    lat1, lng1, lat2, lng2 = map(radians, [lat1, lng1, lat2, lng2])
    
    # Haversine formula
    dlat = lat2 - lat1
    dlng = lng2 - lng1
    a = sin(dlat/2)**2 + cos(lat1) * cos(lat2) * sin(dlng/2)**2
    c = 2 * asin(sqrt(a))
    r = 6371000  # Radius of earth in meters
    return c * r


def get_nearby_users_from_firestore(
    driver_lat: float, 
    driver_lng: float, 
    radius_meters: float = 300
) -> List[dict]:
    """
    Query Firestore for users within radius_meters of driver location.
    Returns list of user docs with id, name, and fcm_token.
    """
    if firestore_db is None:
        return []
    
    try:
        users_ref = firestore_db.collection('users')
        users_snap = users_ref.stream()
        
        nearby_users = []
        for user_doc in users_snap:
            user_data = user_doc.to_dict() or {}
            user_role = user_data.get('role', '')
            
            # Only include public users (people requesting ambulance)
            if user_role != 'public':
                continue
            
            location = user_data.get('location', {})
            user_lat = location.get('lat', 0)
            user_lng = location.get('lng', 0)
            
            # Skip invalid locations
            if user_lat == 0 and user_lng == 0:
                continue
            
            # Calculate distance
            distance = haversine_distance(driver_lat, driver_lng, user_lat, user_lng)
            
            # Include if within radius
            if distance <= radius_meters:
                nearby_users.append({
                    'user_id': user_doc.id,
                    'name': user_data.get('name', 'User'),
                    'fcm_token': user_data.get('fcm_token', ''),
                    'distance': distance,
                })
        
        logger.info(f"Found {len(nearby_users)} nearby users within {radius_meters}m")
        return nearby_users
    except Exception as e:
        logger.error(f"Error querying nearby users: {e}")
        return []


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
    """Toggle emergency status with instant FCM alert push to nearby users"""
    try:
        # Best-effort legacy MongoDB status update when JWT/ObjectId auth is available.
        # Instant push should still work even if legacy auth/storage is not used.
        if users_collection is not None and authorization:
            try:
                token = authorization.replace("Bearer ", "")
                user_id = verify_token(token)
                users_collection.update_one(
                    {"_id": ObjectId(user_id)},
                    {"$set": {"emergency_active": request.active, "updated_at": datetime.utcnow()}},
                )
                logger.info(f"Emergency status updated for legacy user: {user_id} - Active: {request.active}")
            except Exception as legacy_error:
                logger.warning(f"Skipping legacy MongoDB emergency update: {legacy_error}")
        
        # ==== INSTANT FCM PUSH TO NEARBY USERS ====
        alert_count = 0
        if request.active and request.latitude is not None and request.longitude is not None:
            try:
                nearby_users = get_nearby_users_from_firestore(request.latitude, request.longitude)
                
                # Extract valid FCM tokens
                fcm_tokens = [u['fcm_token'] for u in nearby_users if u.get('fcm_token')]
                alert_count = len(fcm_tokens)
                
                if fcm_tokens and messaging is not None:
                    logger.info(f"Sending instant FCM to {len(fcm_tokens)} nearby users")
                    
                    try:
                        message = messaging.MulticastMessage(
                            notification=messaging.Notification(
                                title="🚨 Emergency Alert!",
                                body="Ambulance coming to your location - move left if safe",
                            ),
                            android=messaging.AndroidConfig(
                                priority="high",
                                notification=messaging.AndroidNotification(
                                    sound="default",
                                    channel_id="emergency_ambulance_channel",
                                    priority="max",
                                ),
                            ),
                            tokens=fcm_tokens,
                        )
                        response = messaging.send_each_for_multicast(message)
                        logger.info(f"Instant FCM sent: {response.success_count} success, {response.failure_count} failed")
                    except Exception as fcm_error:
                        logger.error(f"FCM send error: {fcm_error}")
                else:
                    logger.warning(f"No valid FCM tokens found for {len(nearby_users)} nearby users")
            except Exception as e:
                logger.error(f"Error in instant FCM push: {e}")
        
        return {
            "message": "Emergency status updated",
            "active": request.active,
            "alerts_sent": alert_count
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Emergency status error: {e}")
        raise HTTPException(status_code=500, detail="Failed to update emergency status")


# ============ NEW OTP-BASED AUTHENTICATION ENDPOINTS ============

@app.post("/register-initiate", tags=["Auth-OTP"])
def register_initiate(email: str, password: str, name: str, role: str):
    """
    Initiate registration with email OTP verification
    - Generates 6-digit OTP and sends to email
    - Returns pending_user_id to use for /verify-otp
    """
    if otp_pending_collection is None or auth_users_collection is None:
        raise HTTPException(status_code=500, detail="Firestore connection failed")
    
    try:
        from auth import generate_otp, send_otp_email, get_password_hash
        
        email = email.strip().lower()

        # Check if email already registered
        existing_user = list(auth_users_collection.where("email", "==", email).limit(1).stream())
        if existing_user:
            raise HTTPException(status_code=400, detail="Email already registered")
        
        # Check pending registration
        existing_pending = list(otp_pending_collection.where("email", "==", email).limit(1).stream())
        if existing_pending:
            raise HTTPException(status_code=400, detail="Email already has pending registration")
        
        # Validate role
        if role not in ["public", "driver"]:
            raise HTTPException(status_code=400, detail="Invalid role")
        
        # Generate OTP
        otp_code = generate_otp()
        
        # Create pending user
        pending_user_doc = {
            "email": email,
            "name": name,
            "password_hash": get_password_hash(password),
            "role": role,
            "otp_code": otp_code,
            "otp_created_at": datetime.utcnow(),
            "attempt_count": 0,
            "resend_count": 0,
            "resend_window_start": datetime.utcnow(),
            "created_at": datetime.utcnow()
        }
        
        pending_ref = otp_pending_collection.document()
        pending_ref.set(pending_user_doc)
        pending_user_id = pending_ref.id
        
        # Send OTP to email
        email_sent = send_otp_email(email, otp_code)
        if not email_sent:
            # Avoid stale pending records when email delivery fails.
            pending_ref.delete()
            raise HTTPException(
                status_code=500,
                detail="Failed to send OTP email. Check SMTP configuration and try again.",
            )
        
        logger.info(f"Registration initiated for: {email} (Pending ID: {pending_user_id})")
        
        return {
            "pending_user_id": pending_user_id,
            "message": "OTP sent to email",
            "email": email
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Register-initiate error: {e}")
        raise HTTPException(status_code=500, detail="Failed to initiate registration")


@app.post("/verify-otp", tags=["Auth-OTP"])
def verify_otp(pending_user_id: str, otp_code: str):
    """
    Verify OTP and complete registration
    - Creates user document in users collection
    - Returns auth token for auto-login
    """
    if otp_pending_collection is None or auth_users_collection is None:
        raise HTTPException(status_code=500, detail="Firestore connection failed")
    
    try:
        from auth import create_access_token
        
        pending_ref = otp_pending_collection.document(pending_user_id)
        pending_snap = pending_ref.get()
        if not pending_snap.exists:
            raise HTTPException(status_code=404, detail="Pending user not found")

        pending_user = pending_snap.to_dict() or {}
        
        # Check expiry (10 minutes)
        otp_age = datetime.utcnow() - pending_user["otp_created_at"]
        if otp_age > timedelta(minutes=10):
            # Delete expired OTP
            pending_ref.delete()
            raise HTTPException(status_code=400, detail="OTP expired. Please register again.")
        
        # Check attempt limit
        if pending_user.get("attempt_count", 0) >= 5:
            pending_ref.delete()
            raise HTTPException(status_code=400, detail="Too many failed attempts. Please register again.")
        
        # Verify OTP
        if pending_user["otp_code"] != otp_code:
            # Increment attempt count
            pending_ref.update({"attempt_count": firestore.Increment(1)})
            raise HTTPException(status_code=400, detail="Invalid OTP. Please try again.")
        
        # Create user document
        user_doc = {
            "email": pending_user["email"],
            "name": pending_user["name"],
            "password": pending_user["password_hash"],
            "role": pending_user["role"],
            "email_verified": True,
            "location": {"lat": 0, "lng": 0},
            "created_at": datetime.utcnow()
        }
        
        # Insert user in Firestore auth collection
        user_ref = auth_users_collection.document()
        user_ref.set(user_doc)
        user_id = user_ref.id

        # Optional driver profile for ambulance tracking in Firestore.
        if pending_user["role"] == "driver" and firestore_db is not None:
            firestore_db.collection("ambulance").document(user_id).set({
                "driverUserId": user_id,
                "driverName": pending_user["name"],
                "email": pending_user["email"],
                "status": "available",
                "is_active": False,
                "location": {"lat": 0, "lng": 0},
                "created_at": datetime.utcnow(),
            })
        
        # Delete pending user
        pending_ref.delete()
        
        # Create token
        token = create_access_token(data={"sub": user_id})
        
        logger.info(f"User registered via OTP: {user_id} ({pending_user['email']})")
        
        return {
            "access_token": token,
            "user_id": user_id,
            "name": pending_user["name"],
            "role": pending_user["role"],
            "message": "Registration successful"
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Verify-OTP error: {e}")
        raise HTTPException(status_code=500, detail="Failed to verify OTP")


@app.post("/resend-otp", tags=["Auth-OTP"])
def resend_otp(pending_user_id: str):
    """
    Resend OTP code to email
    - Rate limited: max 5 resends per hour
    """
    if otp_pending_collection is None:
        raise HTTPException(status_code=500, detail="Firestore connection failed")
    
    try:
        from auth import generate_otp, send_otp_email
        
        pending_ref = otp_pending_collection.document(pending_user_id)
        pending_snap = pending_ref.get()
        if not pending_snap.exists:
            raise HTTPException(status_code=404, detail="Pending user not found")

        pending_user = pending_snap.to_dict() or {}
        
        # Check resend limit (5 per hour)
        resend_window_start = pending_user.get("resend_window_start", datetime.utcnow())
        time_since_window = datetime.utcnow() - resend_window_start
        
        if time_since_window > timedelta(hours=1):
            # Reset window
            pending_ref.update({"resend_count": 1, "resend_window_start": datetime.utcnow()})
        else:
            if pending_user.get("resend_count", 0) >= 5:
                raise HTTPException(status_code=429, detail="Too many resend attempts. Try again after 1 hour.")
            
            # Increment resend count
            pending_ref.update({"resend_count": firestore.Increment(1)})
        
        # Generate new OTP
        otp_code = generate_otp()
        
        # Update OTP in pending user
        pending_ref.update(
            {
                "otp_code": otp_code,
                "otp_created_at": datetime.utcnow(),
                "attempt_count": 0,
            }
        )
        
        # Send OTP to email
        email_sent = send_otp_email(pending_user["email"], otp_code)
        if not email_sent:
            raise HTTPException(
                status_code=500,
                detail="Failed to resend OTP email. Check SMTP configuration and try again.",
            )
        
        logger.info(f"OTP resent for: {pending_user['email']}")
        
        return {
            "message": "OTP resent to email",
            "email": pending_user["email"]
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Resend-OTP error: {e}")
        raise HTTPException(status_code=500, detail="Failed to resend OTP")


@app.post("/login-email", tags=["Auth-OTP"])
def login_email(email: str, password: str):
    """
    Login with email and password
    - If email not verified, returns pending_user_id to complete OTP verification
    """
    if auth_users_collection is None:
        raise HTTPException(status_code=500, detail="Firestore connection failed")
    
    try:
        from auth import verify_password, create_access_token
        
        email = email.strip().lower()

        # Find user by email
        users = list(auth_users_collection.where("email", "==", email).limit(1).stream())
        if not users:
            raise HTTPException(status_code=401, detail="Invalid email or password")

        user = users[0].to_dict() or {}
        user_id = users[0].id
        
        # Verify password
        if not verify_password(password, user.get("password", "")):
            raise HTTPException(status_code=401, detail="Invalid email or password")
        
        # Check if email verified
        if not user.get("email_verified", False):
            # Check if there's a pending user for this email
            pending = list(otp_pending_collection.where("email", "==", email).limit(1).stream())
            if pending:
                return {
                    "status": "pending_verification",
                    "pending_user_id": pending[0].id,
                    "message": "Email not verified. Complete OTP verification."
                }
            else:
                # Create pending user for verification
                from auth import generate_otp, send_otp_email, get_password_hash
                otp_code = generate_otp()
                
                pending_doc = {
                    "email": email,
                    "name": user.get("name", ""),
                    "password_hash": user["password"],
                    "role": user.get("role", "public"),
                    "otp_code": otp_code,
                    "otp_created_at": datetime.utcnow(),
                    "attempt_count": 0,
                    "resend_count": 0,
                    "resend_window_start": datetime.utcnow(),
                    "created_at": datetime.utcnow()
                }
                
                pending_ref = otp_pending_collection.document()
                pending_ref.set(pending_doc)
                email_sent = send_otp_email(email, otp_code)
                if not email_sent:
                    pending_ref.delete()
                    raise HTTPException(
                        status_code=500,
                        detail="Failed to send OTP email. Check SMTP configuration and try again.",
                    )
                
                return {
                    "status": "pending_verification",
                    "pending_user_id": pending_ref.id,
                    "message": "Email not verified. OTP sent."
                }

        token = create_access_token(data={"sub": user_id})
        
        logger.info(f"User logged in via email: {user_id}")
        
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
        logger.error(f"Login-email error: {e}")
        raise HTTPException(status_code=500, detail="Login failed")


@app.post("/migrate-to-email", tags=["Auth-OTP"])
def migrate_to_email(old_mobile: str, email: str, new_password: str):
    """
    Migrate old mobile-based account to email-based verification
    - Finds user by mobile
    - Adds email and sends OTP verification
    """
    if auth_users_collection is None or otp_pending_collection is None:
        raise HTTPException(status_code=500, detail="Firestore connection failed")
    
    try:
        from auth import generate_otp, send_otp_email, get_password_hash
        
        email = email.strip().lower()

        # Find user by mobile
        users = list(auth_users_collection.where("mobile", "==", old_mobile).limit(1).stream())
        if not users:
            raise HTTPException(status_code=404, detail="User not found")
        user = users[0].to_dict() or {}
        
        # Check if email already exists
        existing_email = list(auth_users_collection.where("email", "==", email).limit(1).stream())
        if existing_email:
            raise HTTPException(status_code=400, detail="Email already registered")
        
        existing_pending = list(otp_pending_collection.where("email", "==", email).limit(1).stream())
        if existing_pending:
            raise HTTPException(status_code=400, detail="Email already has pending registration")
        
        # Generate OTP
        otp_code = generate_otp()
        hashed_password = get_password_hash(new_password)
        
        # Create pending user for email verification
        pending_doc = {
            "email": email,
            "name": user.get("name", ""),
            "password_hash": hashed_password,
            "role": user.get("role", "public"),
            "otp_code": otp_code,
            "otp_created_at": datetime.utcnow(),
            "attempt_count": 0,
            "resend_count": 0,
            "resend_window_start": datetime.utcnow(),
            "old_user_id": users[0].id,
            "created_at": datetime.utcnow()
        }
        
        pending_ref = otp_pending_collection.document()
        pending_ref.set(pending_doc)
        pending_user_id = pending_ref.id
        
        # Send OTP
        email_sent = send_otp_email(email, otp_code)
        if not email_sent:
            pending_ref.delete()
            raise HTTPException(
                status_code=500,
                detail="Failed to send OTP email for migration. Check SMTP configuration and try again.",
            )
        
        logger.info(f"Migration initiated for user: {users[0].id} to email: {email}")
        
        return {
            "pending_user_id": pending_user_id,
            "message": "OTP sent to email for migration",
            "email": email
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Migrate-to-email error: {e}")
        raise HTTPException(status_code=500, detail="Migration failed")


class NotificationRequest(BaseModel):
    token: str = Field(..., description="FCM device token")
    title: str = Field(default="🚨 Emergency Alert", description="Notification title")
    body: str = Field(default="🚨 Ambulance coming - move left", description="Notification body")


@app.post("/send-notification", tags=["Notifications"])
@app.post("/send-notification/", tags=["Notifications"])
def send_notification(request: NotificationRequest):
    """Send FCM push notification to a specific device token"""
    if messaging is None:
        raise HTTPException(status_code=500, detail="Firebase messaging not available")

    try:
        message = messaging.Message(
            notification=messaging.Notification(
                title=request.title,
                body=request.body,
            ),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    sound="default",
                    channel_id="emergency_ambulance_channel",
                    priority="max",
                ),
            ),
            token=request.token,
        )
        response = messaging.send(message)
        logger.info(f"FCM notification sent: {response}")
        return {"message": "Notification sent", "response": response}
    except Exception as e:
        logger.error(f"FCM send error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to send notification: {str(e)}")


@app.post("/send-notification-batch", tags=["Notifications"])
def send_notification_batch(tokens: List[str], title: str = "🚨 Emergency Alert", body: str = "🚨 Ambulance coming - move left"):
    """Send FCM push notification to multiple device tokens"""
    if messaging is None:
        raise HTTPException(status_code=500, detail="Firebase messaging not available")

    try:
        valid_tokens = [t for t in tokens if t and t.strip()]
        if not valid_tokens:
            return {"message": "No valid tokens", "success_count": 0}

        message = messaging.MulticastMessage(
            notification=messaging.Notification(
                title=title,
                body=body,
            ),
            android=messaging.AndroidConfig(
                priority="high",
                notification=messaging.AndroidNotification(
                    sound="default",
                    channel_id="emergency_ambulance_channel",
                    priority="max",
                ),
            ),
            tokens=valid_tokens,
        )
        response = messaging.send_each_for_multicast(message)
        logger.info(f"FCM batch: {response.success_count} sent, {response.failure_count} failed")
        return {
            "message": "Batch sent",
            "success_count": response.success_count,
            "failure_count": response.failure_count,
        }
    except Exception as e:
        logger.error(f"FCM batch error: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to send batch notification: {str(e)}")


# Run with: uvicorn main:app --reload
# The FastAPI app will be served at http://127.0.0.1:8000
# Swagger UI documentation: http://127.0.0.1:8000/docs
# ReDoc documentation: http://127.0.0.1:8000/redoc
