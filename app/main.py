from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.utils import get_openapi
from contextlib import asynccontextmanager
import logging

from app.config import settings
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
    title=settings.PROJECT_NAME,
    version=settings.API_VERSION,
    description="""Participation tracking service managing user activity participation, waitlists, and attendance.

Features PostgreSQL stored procedures, JWT authentication, and comprehensive activity lifecycle tracking.

## Key Features
- Activity participation tracking (join/leave/waitlist)
- Attendance management (check-in/check-out)
- Waitlist automation (auto-confirm when slots available)
- Stored procedure architecture (database-first design)
- Rate limiting on sensitive operations

## Architecture
- Database: PostgreSQL with `activity` schema
- Auth: JWT Bearer tokens from auth-api
- Observability: Prometheus metrics, structured logging""",
    docs_url="/docs" if settings.ENABLE_DOCS else None,
    redoc_url="/redoc" if settings.ENABLE_DOCS else None,
    openapi_url="/openapi.json" if settings.ENABLE_DOCS else None,
    contact={"name": "Activity Platform Team", "email": "dev@activityapp.com"},
    license_info={"name": "Proprietary"},
    lifespan=lifespan
)


def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema
    openapi_schema = get_openapi(
        title=settings.PROJECT_NAME,
        version=settings.API_VERSION,
        description=app.description,
        routes=app.routes,
    )
    openapi_schema["components"]["securitySchemes"] = {
        "BearerAuth": {
            "type": "http",
            "scheme": "bearer",
            "bearerFormat": "JWT",
            "description": "Enter JWT token from auth-api"
        }
    }
    openapi_schema["security"] = [{"BearerAuth": []}]
    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi

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
