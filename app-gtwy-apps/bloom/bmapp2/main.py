"""
BLOOM Sample FastAPI Application 2 for Azure Container Apps with Application Gateway
Demonstrates:
- Health check endpoints
- Analytics and reporting functionality
- Environment variable usage
- Key Vault secret integration
- Path-based routing with root_path="/app2"
- Bloom tenant specific analytics features
"""

import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List
from uuid import uuid4

from fastapi import FastAPI, HTTPException, Query
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
ROOT_PATH = os.getenv("ROOT_PATH", "/app2")
APP_NAME = os.getenv("APP_NAME", "BLOOM-App2")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
DATABASE_URL = os.getenv("DATABASE_URL")  # From Key Vault
SECRET_KEY = os.getenv("SECRET_KEY")  # From Key Vault

# Initialize FastAPI app with path prefix for Application Gateway routing
app = FastAPI(
    title=f"{APP_NAME} Analytics API",
    description="BLOOM FastAPI application 2 for analytics and reporting in multi-tenant Azure Container Apps",
    version="1.0.0",
    root_path=ROOT_PATH,
    docs_url=f"{ROOT_PATH}/docs",
    redoc_url=f"{ROOT_PATH}/redoc"
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# In-memory storage for demo analytics data
analytics_data = {
    "page_views": [],
    "user_sessions": [],
    "content_interactions": [],
    "api_metrics": []
}


@app.get("/")
async def root() -> Dict[str, str]:
    """Root endpoint"""
    return {
        "service": APP_NAME,
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "tenant": "bloom",
        "app": "bmapp2",
        "root_path": ROOT_PATH,
        "status": "running",
        "type": "analytics_api"
    }


@app.get("/health")
async def health_check() -> Dict[str, Any]:
    """
    Health check endpoint for Application Gateway health probes
    Returns 200 OK if service is healthy
    """
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": ENVIRONMENT,
        "tenant": "bloom",
        "app": "bmapp2",
        "root_path": ROOT_PATH,
        "checks": {
            "api": "ok",
            "analytics_engine": "ok",
            "secrets_loaded": "ok" if SECRET_KEY else "missing"
        }
    }


@app.get("/health/ready")
async def readiness_check() -> Dict[str, Any]:
    """
    Readiness probe endpoint for Container Apps
    Checks if service is ready to accept traffic
    """
    checks = {
        "environment_vars": "ok",
        "secrets": "ok" if SECRET_KEY else "fail",
        "analytics_storage": "ok"
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
        "tenant": "bloom",
        "app": "bmapp2",
        "checks": checks
    }


@app.get("/health/live")
async def liveness_check() -> Dict[str, str]:
    """
    Liveness probe endpoint for Container Apps
    Simple check to verify the application is running
    """
    return {
        "status": "alive",
        "timestamp": datetime.utcnow().isoformat(),
        "tenant": "bloom",
        "app": "bmapp2"
    }


@app.get("/api/info")
async def get_info() -> Dict[str, Any]:
    """
    Get application configuration info (non-sensitive)
    """
    return {
        "service": APP_NAME,
        "tenant": "bloom",
        "app": "bmapp2",
        "environment": ENVIRONMENT,
        "root_path": ROOT_PATH,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "analytics_data_points": sum(len(data) for data in analytics_data.values()),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.post("/api/analytics/track")
async def track_event(event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Track analytics event
    """
    event = {
        "id": str(uuid4()),
        "timestamp": datetime.utcnow().isoformat(),
        "tenant": "bloom",
        "app": "bmapp2",
        **event_data
    }
    
    event_type = event_data.get("type", "unknown")
    
    if event_type == "page_view":
        analytics_data["page_views"].append(event)
    elif event_type == "user_session":
        analytics_data["user_sessions"].append(event)
    elif event_type == "content_interaction":
        analytics_data["content_interactions"].append(event)
    else:
        analytics_data["api_metrics"].append(event)
    
    logger.info(f"Tracked event: {event_type} for bloom tenant")
    
    return {
        "status": "tracked",
        "event_id": event["id"],
        "event_type": event_type,
        "tenant": "bloom",
        "timestamp": event["timestamp"]
    }


@app.get("/api/analytics/dashboard")
async def get_dashboard_data(
    period: str = Query("24h", description="Time period: 1h, 24h, 7d, 30d")
) -> Dict[str, Any]:
    """
    Get analytics dashboard data for BLOOM tenant
    """
    now = datetime.utcnow()
    
    # Calculate time window based on period
    if period == "1h":
        start_time = now - timedelta(hours=1)
    elif period == "24h":
        start_time = now - timedelta(days=1)
    elif period == "7d":
        start_time = now - timedelta(days=7)
    elif period == "30d":
        start_time = now - timedelta(days=30)
    else:
        start_time = now - timedelta(days=1)
    
    # Generate sample analytics data for BLOOM tenant
    dashboard_data = {
        "tenant": "bloom",
        "app": "bmapp2",
        "period": period,
        "start_time": start_time.isoformat(),
        "end_time": now.isoformat(),
        "metrics": {
            "total_page_views": len(analytics_data["page_views"]) + 15000,
            "unique_users": 2500,
            "session_duration_avg": "4m 32s",
            "bounce_rate": "32%",
            "content_engagement": "68%"
        },
        "top_content": [
            {"title": "AI Content Analysis Guide", "views": 850, "engagement": "85%"},
            {"title": "Media Processing Tutorial", "views": 720, "engagement": "78%"},
            {"title": "Advanced Analytics Report", "views": 650, "engagement": "82%"},
            {"title": "Custom Integrations Setup", "views": 480, "engagement": "74%"}
        ],
        "user_activity": {
            "peak_hours": ["10:00-12:00", "14:00-16:00", "19:00-21:00"],
            "device_breakdown": {
                "desktop": "55%",
                "mobile": "35%",
                "tablet": "10%"
            },
            "geographic_distribution": {
                "north_america": "45%",
                "europe": "35%",
                "asia_pacific": "20%"
            }
        },
        "performance": {
            "api_response_time": "125ms",
            "uptime": "99.8%",
            "error_rate": "0.2%",
            "cache_hit_rate": "87%"
        },
        "timestamp": now.isoformat()
    }
    
    return dashboard_data


@app.get("/api/analytics/reports")
async def get_analytics_reports() -> Dict[str, Any]:
    """
    Get available analytics reports for BLOOM tenant
    """
    return {
        "tenant": "bloom",
        "app": "bmapp2",
        "available_reports": [
            {
                "id": "content_performance",
                "name": "Content Performance Analysis",
                "description": "Detailed analysis of content engagement and performance",
                "frequency": "daily"
            },
            {
                "id": "user_behavior",
                "name": "User Behavior Insights",
                "description": "User journey analysis and behavior patterns",
                "frequency": "weekly"
            },
            {
                "id": "media_analytics",
                "name": "Media Processing Analytics",
                "description": "Media upload, processing, and consumption metrics",
                "frequency": "daily"
            },
            {
                "id": "api_usage",
                "name": "API Usage Statistics",
                "description": "API endpoint usage, performance, and error analysis",
                "frequency": "hourly"
            }
        ],
        "custom_reports": {
            "enabled": True,
            "max_custom_reports": 10,
            "current_custom_reports": 3
        },
        "export_formats": ["JSON", "CSV", "PDF", "Excel"],
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/analytics/realtime")
async def get_realtime_metrics() -> Dict[str, Any]:
    """
    Get real-time analytics metrics for BLOOM tenant
    """
    now = datetime.utcnow()
    
    return {
        "tenant": "bloom",
        "app": "bmapp2",
        "realtime_metrics": {
            "active_users": 145,
            "concurrent_sessions": 89,
            "api_calls_per_minute": 267,
            "data_processing_queue": 12,
            "cache_operations_per_second": 45,
            "error_count_last_minute": 2
        },
        "live_events": [
            {"type": "user_login", "count": 8, "last_event": "2 seconds ago"},
            {"type": "content_upload", "count": 3, "last_event": "15 seconds ago"},
            {"type": "media_processing", "count": 5, "last_event": "8 seconds ago"},
            {"type": "api_call", "count": 156, "last_event": "1 second ago"}
        ],
        "system_health": {
            "cpu_usage": "45%",
            "memory_usage": "62%",
            "disk_usage": "34%",
            "network_io": "moderate"
        },
        "alerts": {
            "active": 0,
            "resolved_today": 2,
            "critical": 0
        },
        "timestamp": now.isoformat(),
        "next_update": (now + timedelta(seconds=30)).isoformat()
    }


@app.get("/api/database/test")
async def test_database() -> Dict[str, Any]:
    """
    Test database connectivity for analytics data
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
            "message": "Database URL is configured for bloom analytics",
            "tenant": "bloom",
            "app": "bmapp2",
            "analytics_tables": ["page_views", "user_sessions", "events", "metrics"],
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
            "tenant": "bloom",
            "app": "bmapp2",
            "message": str(exc) if ENVIRONMENT == "dev" else "An error occurred"
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