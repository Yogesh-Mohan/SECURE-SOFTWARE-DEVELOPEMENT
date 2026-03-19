from fastapi import FastAPI, HTTPException, status
from pymongo import MongoClient
from pymongo.errors import ServerSelectionTimeoutError, OperationFailure
from bson import ObjectId
from pydantic import BaseModel, Field, ConfigDict, ValidationError
from typing import List, Optional
import os
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Ambulance Backend API",
    description="Backend server for ambulance service",
    version="1.0.0"
)

# MongoDB connection configuraytion
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
    password: Optional[str] = Field(default=None, min_length=6, description="Optional password field")
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


# Routes
@app.get("/", response_model=dict, tags=["Health"])
def read_root():
    """Health check endpoint"""
    logger.info("Health check endpoint called")
    return {"message": "Backend working"}


@app.post(
    "/add-user",
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
        user_dict.pop("password", None)
        result = users_collection.insert_one(user_dict)
        logger.info(f"User added with ID: {result.inserted_id}")
        
        # Convert ObjectId to string for serialization
        user_response = user_dict
        
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


# Run with: uvicorn main:app --reload
# The FastAPI app will be served at http://127.0.0.1:8000
# Swagger UI documentation: http://127.0.0.1:8000/docs
# ReDoc documentation: http://127.0.0.1:8000/redoc
