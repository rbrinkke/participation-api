from fastapi import APIRouter
from datetime import datetime

router = APIRouter(prefix="/api/v1/participation", tags=["health"])


@router.get("/health")
async def health_check():
    """Health check endpoint (no auth required)"""
    return {
        "status": "healthy",
        "service": "participation-api",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat()
    }
