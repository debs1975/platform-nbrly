"""
NBRLY App1 - FastAPI Application
Demonstrates path-based routing at /nbapp1
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

# Initialize FastAPI app with root_path for Application Gateway routing
app = FastAPI(
    title="NBRLY App1",
    description="NBRLY Tenant - App1 - Basic API Service",
    version="1.0.0",
    root_path="/nbapp1"
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


@app.get("/")
async def root() -> Dict[str, str]:
    """Root endpoint for NBRLY App1"""
    return {
        "service": "NBRLY App1",
        "tenant": "nbrly",
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "root_path": "/nbapp1",
        "status": "running"
    }


@app.get("/health")
async def health_check() -> Dict[str, Any]:
    """Health check endpoint for Container Apps health probes"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": ENVIRONMENT,
        "service": "nbapp1",
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
        "service": "nbapp1",
        "tenant": "nbrly",
        "environment": ENVIRONMENT,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/items")
async def list_items() -> Dict[str, Any]:
    """List items - Demo endpoint"""
    return {
        "items": [
            {"id": 1, "name": "Item 1", "description": "First item from nbapp1"},
            {"id": 2, "name": "Item 2", "description": "Second item from nbapp1"}
        ],
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/items/{item_id}")
async def get_item(item_id: int) -> Dict[str, Any]:
    """Get a specific item"""
    if item_id < 1:
        raise HTTPException(status_code=400, detail="Invalid item ID")
    
    return {
        "id": item_id,
        "name": f"Item {item_id}",
        "description": f"Item details for ID {item_id} from nbapp1",
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


# Root API endpoint
@app.get("/app1")
async def app1_root():
    logger.info("Root endpoint /app1 accessed")
    return JSONResponse(
        status_code=200,
        content={"message": "nbapp1 is running", "tenant": "nbrly", "app": "nbapp1"}
    )

@app.get("/app1/health")
async def app1_health():
    logger.info("Health check requested")
    return JSONResponse(status_code=200, content={"status": "healthy"})

@app.get("/app1/info")
async def app1_info():
    return JSONResponse(
        status_code=200,
        content={
            "tenant": "nbrly",
            "app": "nbapp1",
            "environment": os.getenv("ENVIRONMENT", "dev"),
            "version": "1.0.0"
        }
    )


if __name__ == "__main__":
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        log_level="info",
        access_log=True
    )
