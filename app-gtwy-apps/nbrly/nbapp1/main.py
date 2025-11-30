"""
NBRLY Sample FastAPI Application 1 for Azure Container Apps with Application Gateway
Demonstrates:
- Health check endpoints
- Database connectivity
- Environment variable usage
- Key Vault secret integration
- Path-based routing with root_path="/app1"
- Bloom tenant specific functionality
"""

import os
import logging
from datetime import datetime
from typing import Dict, Any

from fastapi import FastAPI, HTTPException, APIRouter
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")
ROOT_PATH = os.getenv("ROOT_PATH", "/app1")
APP_NAME = os.getenv("APP_NAME", "NBRLY-App1")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
DATABASE_URL = os.getenv("DATABASE_URL", None)  # From Key Vault
SECRET_KEY = os.getenv("SECRET_KEY", None)  # From Key Vault

# Initialize FastAPI app
app = FastAPI(
    title=f"{APP_NAME} API",
    description="NBRLY FastAPI application 1 for multi-tenant Azure Container Apps deployment",
    version="1.0.0",
    docs_url=f"{ROOT_PATH}/docs",
    openapi_url=f"{ROOT_PATH}/openapi.json",
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create routers
health_router = APIRouter()
app_router = APIRouter()

@app_router.get("/")
async def root() -> Dict[str, str]:
    """Root endpoint"""
    return {
        "service": APP_NAME,
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "tenant": "nbrly",
        "app": "nbapp1",
        "status": "running"
    }


@health_router.get("/health")
async def health_check() -> Dict[str, Any]:
    """
    Health check endpoint for Application Gateway health probes
    Returns 200 OK if service is healthy
    """
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": ENVIRONMENT,
        "tenant": "nbrly",
        "app": "nbapp1",
        "checks": {
            "api": "ok",
            "secrets_loaded": "ok" if SECRET_KEY else "missing"
        }
    }


@health_router.get("/health/ready")
async def readiness_check() -> Dict[str, Any]:
    """
    Readiness probe endpoint for Container Apps
    Checks if service is ready to accept traffic
    """
    checks = {
        "environment_vars": "ok",
        "secrets": "ok" if SECRET_KEY else "fail"
    }
    
    # Check database connectivity (basic check)
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
        "tenant": "nbrly",
        "app": "nbapp1",
        "checks": checks
    }


@health_router.get("/health/live")
async def liveness_check() -> Dict[str, str]:
    """
    Liveness probe endpoint for Container Apps
    Simple check to verify the application is running
    """
    return {
        "status": "alive",
        "timestamp": datetime.utcnow().isoformat(),
        "tenant": "nbrly",
        "app": "nbapp1"
    }


@app_router.get("/api/info")
async def get_info() -> Dict[str, Any]:
    """
    Get application configuration info (non-sensitive)
    """
    return {
        "service": APP_NAME,
        "tenant": "nbrly",
        "app": "nbapp1",
        "environment": ENVIRONMENT,
        "root_path": ROOT_PATH,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "timestamp": datetime.utcnow().isoformat()
    }


@app_router.get("/api/nbrly/services")
async def get_nbrly_services() -> Dict[str, Any]:
    """
    Get NBRLY tenant specific services
    """
    return {
        "tenant": "nbrly",
        "app": "nbapp1",
        "services": [
            "content_management",
            "media_processing",
            "user_engagement",
            "analytics_engine"
        ],
        "capabilities": {
            "max_content_items": 10000,
            "storage_limit_gb": 500,
            "concurrent_users": 2000,
            "api_calls_per_day": 100000
        },
        "features": {
            "real_time_processing": True,
            "ai_content_analysis": True,
            "advanced_analytics": True,
            "custom_integrations": True
        },
        "timestamp": datetime.utcnow().isoformat()
    }


@app_router.get("/api/nbrly/content")
async def get_nbrly_content() -> Dict[str, Any]:
    """
    Get NBRLY tenant content management info
    """
    return {
        "tenant": "nbrly",
        "app": "nbapp1",
        "content_stats": {
            "total_items": 1500,
            "published": 1200,
            "draft": 250,
            "archived": 50,
            "categories": ["articles", "videos", "images", "documents"]
        },
        "media_processing": {
            "image_formats_supported": ["JPG", "PNG", "GIF", "WebP"],
            "video_formats_supported": ["MP4", "AVI", "MOV", "WebM"],
            "max_file_size_mb": 100,
            "processing_queue": 5
        },
        "timestamp": datetime.utcnow().isoformat()
    }


@app_router.get("/api/database/test")
async def test_database() -> Dict[str, Any]:
    """
    Test database connectivity
    """
    if not DATABASE_URL:
        raise HTTPException(
            status_code=503,
            detail="Database connection string not configured"
        )
    
    try:
        # Placeholder for actual database connection test
        # In production, you would:
        # 1. Import psycopg2 or asyncpg
        # 2. Create a connection
        # 3. Execute a simple query (SELECT 1)
        # 4. Close the connection
        
        return {
            "status": "database_url_configured",
            "message": "Database URL is configured for nbrly tenant",
            "tenant": "nbrly",
            "app": "nbapp1",
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Database test failed: {str(e)}")
        raise HTTPException(
            status_code=503,
            detail=f"Database connection test failed: {str(e)}"
        )


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(f"Unhandled exception in {APP_NAME}: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "tenant": "nbrly",
            "app": "nbapp1",
            "message": str(exc) if ENVIRONMENT == "dev" else "An error occurred"
        }
    )

# Mount routers
# App logic and Health checks must be under ROOT_PATH
app.include_router(app_router, prefix=ROOT_PATH)
app.include_router(health_router, prefix=ROOT_PATH)


if __name__ == "__main__":
    # Run with uvicorn
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        log_level="info",
        access_log=True
    )