"""
NBRLY App2 - FastAPI Application
Demonstrates path-based routing at /nbapp2
Task Management API
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
class Task(BaseModel):
    id: Optional[int] = None
    title: str
    description: str
    completed: bool = False
    created_at: Optional[str] = None

# Initialize FastAPI app
app = FastAPI(
    title="NBRLY App2",
    description="NBRLY Tenant - App2 - Task Management Service",
    version="1.0.0",
    root_path="/nbapp2"
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

# In-memory task storage (replace with database in production)
tasks_db: Dict[int, Task] = {}
task_counter = 0


@app.get("/")
async def root() -> Dict[str, str]:
    """Root endpoint for NBRLY App2"""
    return {
        "service": "NBRLY App2",
        "tenant": "nbrly",
        "version": "1.0.0",
        "environment": ENVIRONMENT,
        "root_path": "/nbapp2",
        "status": "running"
    }


@app.get("/health")
async def health_check() -> Dict[str, Any]:
    """Health check endpoint"""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "environment": ENVIRONMENT,
        "service": "nbapp2",
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
        "service": "nbapp2",
        "tenant": "nbrly",
        "environment": ENVIRONMENT,
        "allowed_origins": ALLOWED_ORIGINS,
        "database_configured": bool(DATABASE_URL),
        "secrets_configured": bool(SECRET_KEY),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/tasks")
async def list_tasks() -> Dict[str, Any]:
    """List all tasks"""
    return {
        "tasks": list(tasks_db.values()),
        "total": len(tasks_db),
        "timestamp": datetime.utcnow().isoformat()
    }


@app.post("/api/tasks")
async def create_task(task: Task) -> Dict[str, Any]:
    """Create a new task"""
    global task_counter
    task_counter += 1
    
    task.id = task_counter
    task.created_at = datetime.utcnow().isoformat()
    
    tasks_db[task.id] = task
    
    return {
        "task": task,
        "message": "Task created successfully",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.get("/api/tasks/{task_id}")
async def get_task(task_id: int) -> Dict[str, Any]:
    """Get a specific task"""
    if task_id not in tasks_db:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    
    return {
        "task": tasks_db[task_id],
        "timestamp": datetime.utcnow().isoformat()
    }


@app.put("/api/tasks/{task_id}")
async def update_task(task_id: int, task_update: Task) -> Dict[str, Any]:
    """Update a task"""
    if task_id not in tasks_db:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    
    existing_task = tasks_db[task_id]
    existing_task.title = task_update.title
    existing_task.description = task_update.description
    existing_task.completed = task_update.completed
    
    return {
        "task": existing_task,
        "message": "Task updated successfully",
        "timestamp": datetime.utcnow().isoformat()
    }


@app.delete("/api/tasks/{task_id}")
async def delete_task(task_id: int) -> Dict[str, Any]:
    """Delete a task"""
    if task_id not in tasks_db:
        raise HTTPException(status_code=404, detail=f"Task {task_id} not found")
    
    deleted_task = tasks_db.pop(task_id)
    
    return {
        "message": "Task deleted successfully",
        "deleted_task": deleted_task,
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
