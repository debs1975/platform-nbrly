"""
Sample FastAPI Application for Azure Container Apps
Demonstrates:
- Health check endpoints
- Database connectivity
- Environment variable usage
- Key Vault secret integration
"""

import os
import logging
from datetime import datetime
from typing import Dict, Any

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

# Initialize FastAPI app with path prefix for routing
app = FastAPI(
    title="NBRLY Sample API",
    description="Sample FastAPI application for Azure Container Apps deployment",
    version="1.0.0",
    root_path="/app1"
)

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
DATABASE_URL = os.getenv("DATABASE_URL")  # From Key Vault
SECRET_KEY = os.getenv("SECRET_KEY")  # From Key Vault

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root() -> Dict[str, str]:
    """Root endpoint"""
    return {
        "service": "NBRLY Sample API",
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "status": "running"
    }


@app.get("/health")
async def health_check() -> Dict[str, Any]:
    """
    Health check endpoint for Container Apps health probes
    Returns 200 OK if service is healthy
    """
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": ENVIRONMENT,
        "checks": {
            "api": "ok",
            "secrets_loaded": "ok" if SECRET_KEY else "missing"
        }
    }


@app.get("/health/ready")
async def readiness_check() -> Dict[str, Any]:
    """
    Readiness probe endpoint
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
        "checks": checks
    }


@app.get("/health/live")
async def liveness_check() -> Dict[str, str]:
    """
    Liveness probe endpoint
    Simple check to verify the application is running
    """
    return {
        "status": "alive",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/info")
async def get_info() -> Dict[str, Any]:
    """
    Get application configuration info (non-sensitive)
    """
    return {
        "environment": ENVIRONMENT,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/database/test")
async def test_database() -> Dict[str, Any]:
    """
    Test database connectivity
    Note: This is a placeholder. Add actual database connection logic.
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
            "message": "Database URL is configured. Add actual connection logic.",
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
    logger.error(f"Unhandled exception: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "message": str(exc) if ENVIRONMENT == "development" else "An error occurred"
        }
    )


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
