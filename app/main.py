from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from app.database import init_db, close_db

logger = logging.getLogger(__name__)
from app.routes import (
    health,
    participation,
    role_management,
    attendance,
    invitations,
    waitlist
)
from app.utils.rate_limit import limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events"""
    # Startup
    logger.info("=== LIFESPAN STARTUP BEGIN ===")
    await init_db()
    logger.info("=== LIFESPAN STARTUP COMPLETE ===")
    yield
    # Shutdown
    logger.info("=== LIFESPAN SHUTDOWN BEGIN ===")
    await close_db()
    logger.info("=== LIFESPAN SHUTDOWN COMPLETE ===")


app = FastAPI(
    title="Participation API",
    description="Activity participation management API",
    version="1.0.0",
    lifespan=lifespan
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Register routers
app.include_router(health.router)
app.include_router(participation.router)
app.include_router(role_management.router)
app.include_router(attendance.router)
app.include_router(invitations.router)
app.include_router(waitlist.router)


if __name__ == "__main__":
    import uvicorn
    from app.config import get_settings

    settings = get_settings()
    uvicorn.run(
        "app.main:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=settings.ENVIRONMENT == "development"
    )
