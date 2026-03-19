# FastAPI Backend API

A simple yet production-ready FastAPI backend with MongoDB integration for ambulance service management.

## Features

- ✅ FastAPI framework with automatic OpenAPI documentation
- ✅ MongoDB integration with pymongo
- ✅ Proper error handling and HTTP status codes
- ✅ Pydantic data validation
- ✅ Structured logging
- ✅ Environment-based configuration
- ✅ Swagger UI for API testing

## Prerequisites

- Python 3.8+
- MongoDB running locally at `mongodb://localhost:27017`
- pip (Python package manager)

## Installation

1. **Install dependencies**:
   ```bash
   pip install fastapi uvicorn pymongo python-dotenv
   ```

2. **Create environment file** (optional):
   ```bash
   cp .env.example .env
   ```
   If you don't create a `.env` file, the app will use default values:
   - MongoDB: `mongodb://localhost:27017`
   - Database: `admin`

## Running the Server

Start the development server with auto-reload:

```bash
uvicorn main:app --reload
```

The server will start at: `http://127.0.0.1:8000`

## API Documentation

Once the server is running, access the interactive API documentation:

### Swagger UI
```
http://127.0.0.1:8000/docs
```

### ReDoc Alternative
```
http://127.0.0.1:8000/redoc
```

## API Endpoints

### 1. Health Check
**GET** `/`
```
Returns: {"message": "Backend working"}
```

### 2. Add User
**POST** `/add-user`

Request body:
```json
{
  "name": "John Doe",
  "role": "public",
  "location": {
    "lat": 12.9716,
    "lng": 77.5946
  }
}
```

Response:
```json
{
  "message": "User added successfully",
  "user_id": "507f1f77bcf86cd799439011",
  "user": {
    "name": "John Doe",
    "role": "public",
    "location": {
      "lat": 12.9716,
      "lng": 77.5946
    }
  }
}
```

### 3. Get All Users
**GET** `/get-users`

Response:
```json
{
  "total": 2,
  "users": [
    {
      "_id": "507f1f77bcf86cd799439011",
      "name": "John Doe",
      "role": "public",
      "location": {
        "lat": 12.9716,
        "lng": 77.5946
      }
    }
  ]
}
```

## Testing with Curl

### Test health check:
```bash
curl http://127.0.0.1:8000/
```

### Add a user:
```bash
curl -X POST "http://127.0.0.1:8000/add-user" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "test user",
    "role": "public",
    "location": {"lat": 0, "lng": 0}
  }'
```

### Get all users:
```bash
curl http://127.0.0.1:8000/get-users
```

## Project Structure

```
.
├── main.py              # Main FastAPI application
├── .env.example         # Environment variables template
└── README.md           # This file
```

## Collections Created in MongoDB

The app automatically references these collections in the `admin` database:
- `users` - Stores user information
- `ambulance` - For ambulance data (ready for implementation)
- `alerts` - For alert data (ready for implementation)

## Configuration

Customize the MongoDB connection by setting environment variables:

```bash
export MONGO_URL="mongodb://localhost:27017"
export DATABASE_NAME="admin"
```

Or create a `.env` file with these values (see `.env.example`).

## Error Handling

The API returns appropriate HTTP status codes:
- **201** - User created successfully
- **400** - Bad request (validation error)
- **500** - Server error (database connection, etc.)

All errors include a descriptive `detail` message.

## Logging

The application uses Python's built-in logging module. Logs are printed to console with INFO level by default. You can modify the log level in `main.py`:

```python
logging.basicConfig(level=logging.DEBUG)  # For more verbose output
```

## Next Steps

You can extend this backend by:
1. Implementing endpoints for `ambulance` and `alerts` collections
2. Adding authentication/authorization (JWT tokens)
3. Adding request rate limiting
4. Implementing pagination for list endpoints
5. Adding database indexing for performance
6. Creating unit tests with pytest
7. Deploying to production (Azure App Service, AWS Lambda, etc.)

## Troubleshooting

### MongoDB Connection Issues
- Ensure MongoDB is running locally
- Check if port 27017 is accessible
- Verify connection string in environment variables

### Port Already in Use
If port 8000 is already in use, specify a different port:
```bash
uvicorn main:app --reload --port 8001
```

### Import Errors
Make sure all dependencies are installed:
```bash
pip install -r requirements.txt
```

## License

This project is provided as-is for development purposes.
