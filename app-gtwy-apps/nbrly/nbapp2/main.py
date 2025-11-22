"""
NBRLY Sample FastAPI Application 2 for Azure Container Apps with Application Gateway
Demonstrates:
- Health check endpoints
- Database connectivity
- Environment variable usage
- Key Vault secret integration
- Path-based routing with root_path="/app2"
- Task management functionality
"""

import os
import logging
from datetime import datetime
from typing import Dict, Any, List

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

# Environment variables
ENVIRONMENT = os.getenv("ENVIRONMENT", "dev")
ROOT_PATH = os.getenv("ROOT_PATH", "/app2")
APP_NAME = os.getenv("APP_NAME", "NBRLY-App2")
ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "*").split(",")
DATABASE_URL = os.getenv("DATABASE_URL")  # From Key Vault
SECRET_KEY = os.getenv("SECRET_KEY")  # From Key Vault

# Initialize FastAPI app with path prefix for Application Gateway routing
app = FastAPI(
    title=f"{APP_NAME} API",
    description="NBRLY FastAPI application 2 for multi-tenant Azure Container Apps deployment",
    version="2.0.0",
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

# In-memory data store for demo
tasks: List[Dict[str, Any]] = []
task_id_counter = 1


@app.get("/")
async def root() -> Dict[str, str]:
    """Root endpoint"""
    return {
        "service": APP_NAME,
        "version": "2.0.0",
        "environment": ENVIRONMENT,
        "tenant": "nbrly",
        "app": "nbapp2",
        "root_path": ROOT_PATH,
        "status": "running",
        "features": ["task_management", "health_checks", "api_info"]
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
        "tenant": "nbrly",
        "app": "nbapp2",
        "root_path": ROOT_PATH,
        "version": "2.0.0",
        "checks": {
            "api": "ok",
            "secrets_loaded": "ok" if SECRET_KEY else "missing",
            "tasks_store": "ok"
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
        "tasks_store": "ok"
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
        "app": "nbapp2",
        "version": "2.0.0",
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
        "tenant": "nbrly",
        "app": "nbapp2",
        "version": "2.0.0"
    }


@app.get("/api/info")
async def get_info() -> Dict[str, Any]:
    """
    Get application configuration info (non-sensitive)
    """
    return {
        "service": APP_NAME,
        "tenant": "nbrly",
        "app": "nbapp2",
        "version": "2.0.0",
        "environment": ENVIRONMENT,
        "root_path": ROOT_PATH,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "tasks_count": len(tasks),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/tasks")
async def get_tasks() -> Dict[str, Any]:
    """
    Get all tasks for NBRLY tenant
    """
    return {
        "tenant": "nbrly",
        "app": "nbapp2",
        "tasks": tasks,
        "count": len(tasks),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.post("/api/tasks")
async def create_task(title: str, description: str = "") -> Dict[str, Any]:
    """
    Create a new task for NBRLY tenant
    """
    global task_id_counter
    
    task = {
        "id": task_id_counter,
        "title": title,
        "description": description,
        "status": "pending",
        "tenant": "nbrly",
        "created_at": datetime.utcnow().isoformat(),
        "updated_at": datetime.utcnow().isoformat()
    }
    
    tasks.append(task)
    task_id_counter += 1
    
    logger.info(f"Created task for nbrly tenant: {task['id']}")
    
    return {
        "message": "Task created for nbrly tenant",
        "task": task
    }


@app.get("/api/tasks/{task_id}")
async def get_task(task_id: int) -> Dict[str, Any]:
    """
    Get a specific task by ID for NBRLY tenant
    """
    task = next((t for t in tasks if t["id"] == task_id), None)
    
    if not task:
        raise HTTPException(status_code=404, detail="Task not found in nbrly tenant")
    
    return task


@app.put("/api/tasks/{task_id}")
async def update_task(task_id: int, status: str) -> Dict[str, Any]:
    """
    Update task status for NBRLY tenant
    """
    task = next((t for t in tasks if t["id"] == task_id), None)
    
    if not task:
        raise HTTPException(status_code=404, detail="Task not found in nbrly tenant")
    
    valid_statuses = ["pending", "in_progress", "completed", "cancelled"]
    if status not in valid_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status. Must be one of: {', '.join(valid_statuses)}"
        )
    
    task["status"] = status
    task["updated_at"] = datetime.utcnow().isoformat()
    
    logger.info(f"Updated nbrly task {task_id} to status: {status}")
    
    return {
        "message": "Task updated for nbrly tenant",
        "task": task
    }


@app.delete("/api/tasks/{task_id}")
async def delete_task(task_id: int) -> Dict[str, str]:
    """
    Delete a task for NBRLY tenant
    """
    global tasks
    
    task = next((t for t in tasks if t["id"] == task_id), None)
    
    if not task:
        raise HTTPException(status_code=404, detail="Task not found in nbrly tenant")
    
    tasks = [t for t in tasks if t["id"] != task_id]
    
    logger.info(f"Deleted nbrly task: {task_id}")
    
    return {
        "message": "Task deleted from nbrly tenant",
        "tenant": "nbrly",
        "task_id": str(task_id)
    }


@app.get("/api/nbrly/analytics")
async def get_nbrly_analytics() -> Dict[str, Any]:
    """
    Get NBRLY tenant specific analytics
    """
    completed_tasks = [t for t in tasks if t["status"] == "completed"]
    pending_tasks = [t for t in tasks if t["status"] == "pending"]
    in_progress_tasks = [t for t in tasks if t["status"] == "in_progress"]
    
    return {
        "tenant": "nbrly",
        "app": "nbapp2",
        "analytics": {
            "total_tasks": len(tasks),
            "completed_tasks": len(completed_tasks),
            "pending_tasks": len(pending_tasks),
            "in_progress_tasks": len(in_progress_tasks),
            "completion_rate": len(completed_tasks) / len(tasks) * 100 if tasks else 0
        },
        "timestamp": datetime.utcnow().isoformat()
    }


@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    """Global exception handler"""
    logger.error(f"Unhandled exception in {APP_NAME}: {str(exc)}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal server error",
            "tenant": "nbrly",
            "app": "nbapp2",
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