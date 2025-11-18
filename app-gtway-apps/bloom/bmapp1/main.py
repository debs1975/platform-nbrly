"""
BLOOM App1 - FastAPI Application
Demonstrates path-based routing at /bmapp1
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
    title="BLOOM App1",
    description="BLOOM Tenant - App1 - Basic API Service",
    version="1.0.0",
    root_path="/bmapp1"
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
    """Root endpoint for BLOOM App1"""
    return {
        "service": "BLOOM App1",
        "tenant": "bloom",
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "root_path": "/bmapp1",
        "status": "running"
    }


@app.get("/health")
async def health_check() -> Dict[str, Any]:
    """Health check endpoint for Container Apps health probes"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": ENVIRONMENT,
        "service": "bmapp1",
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
        "service": "bmapp1",
        "tenant": "bloom",
        "environment": ENVIRONMENT,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/products")
async def list_products() -> Dict[str, Any]:
    """List products - Demo endpoint"""
    return {
        "products": [
            {"id": 1, "name": "Product 1", "price": 99.99, "description": "First product from bmapp1"},
            {"id": 2, "name": "Product 2", "price": 149.99, "description": "Second product from bmapp1"}
        ],
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/products/{product_id}")
async def get_product(product_id: int) -> Dict[str, Any]:
    """Get a specific product"""
    if product_id < 1:
        raise HTTPException(status_code=400, detail="Invalid product ID")
    
    return {
        "id": product_id,
        "name": f"Product {product_id}",
        "price": 99.99 * product_id,
        "description": f"Product details for ID {product_id} from bmapp1",
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
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=port,
        log_level="info",
        access_log=True
    )
