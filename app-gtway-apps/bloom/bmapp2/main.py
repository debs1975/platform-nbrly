"""
BLOOM App2 - FastAPI Application
Demonstrates path-based routing at /bmapp2
User Management API
"""

import os
import logging
from datetime import datetime
from typing import Dict, Any, List, Optional
from pydantic import BaseModel

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Pydantic models for request/response
class User(BaseModel):
    id: Optional[int] = None
    email: str
    full_name: str
    is_active: bool = True
    created_at: Optional[str] = None

# Initialize FastAPI app
app = FastAPI(
    title="BLOOM App2",
    description="BLOOM Tenant - App2 - User Management Service",
    version="1.0.0",
    root_path="/bmapp2"
)

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
DATABASE_URL = os.getenv("DATABASE_URL")
SECRET_KEY = os.getenv("SECRET_KEY")

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory user storage (replace with database in production)
users_db: Dict[int, User] = {}
user_counter = 0


@app.get("/")
async def root() -> Dict[str, str]:
    """Root endpoint for BLOOM App2"""
    return {
        "service": "BLOOM App2",
        "tenant": "bloom",
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "root_path": "/bmapp2",
        "status": "running"
    }


@app.get("/health")
async def health_check() -> Dict[str, Any]:
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": ENVIRONMENT,
        "service": "bmapp2",
        "checks": {
            "api": "ok",
            "secrets_loaded": "ok" if SECRET_KEY else "missing"
        }
    }


@app.get("/health/ready")
async def readiness_check() -> Dict[str, Any]:
    """Readiness probe endpoint"""
    checks = {
        "environment_vars": "ok",
        "secrets": "ok" if SECRET_KEY else "fail"
    }
    
    if DATABASE_URL:
        checks["database_config"] = "ok"
    else:
        checks["database_config"] = "missing"
    
    is_ready = all(status == "ok" for status in checks.values())
    
    if not is_ready:
        raise HTTPException(status_code=503, detail="Service not ready")
    
    return {
        "status": "ready",
        "timestamp": datetime.utcnow().isoformat(),
        "checks": checks
    }


@app.get("/health/live")
async def liveness_check() -> Dict[str, str]:
    """Liveness probe endpoint"""
    return {
        "status": "alive",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/info")
async def get_info() -> Dict[str, Any]:
    """Get application configuration info"""
    return {
        "service": "bmapp2",
        "tenant": "bloom",
        "environment": ENVIRONMENT,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/users")
async def list_users() -> Dict[str, Any]:
    """List all users"""
    return {
        "users": list(users_db.values()),
        "total": len(users_db),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.post("/api/users")
async def create_user(user: User) -> Dict[str, Any]:
    """Create a new user"""
    global user_counter
    user_counter += 1
    
    user.id = user_counter
    user.created_at = datetime.utcnow().isoformat()
    
    users_db[user.id] = user
    
    return {
        "user": user,
        "message": "User created successfully",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/users/{user_id}")
async def get_user(user_id: int) -> Dict[str, Any]:
    """Get a specific user"""
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail=f"User {user_id} not found")
    
    return {
        "user": users_db[user_id],
        "timestamp": datetime.utcnow().isoformat()
    }


@app.put("/api/users/{user_id}")
async def update_user(user_id: int, user_update: User) -> Dict[str, Any]:
    """Update a user"""
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail=f"User {user_id} not found")
    
    existing_user = users_db[user_id]
    existing_user.email = user_update.email
    existing_user.full_name = user_update.full_name
    existing_user.is_active = user_update.is_active
    
    return {
        "user": existing_user,
        "message": "User updated successfully",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.delete("/api/users/{user_id}")
async def delete_user(user_id: int) -> Dict[str, Any]:
    """Delete a user"""
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail=f"User {user_id} not found")
    
    deleted_user = users_db.pop(user_id)
    
    return {
        "message": "User deleted successfully",
        "deleted_user": deleted_user,
        "timestamp": datetime.utcnow().isoformat()
    }


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "message": str(exc) if ENVIRONMENT == "development" else "An error occurred"
        }
    )


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8001"))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        log_level="info",
        access_log=True
    )
