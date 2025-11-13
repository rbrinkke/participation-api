import asyncpg
from app.config import get_settings

settings = get_settings()

# Global pool instance
db_pool = None


async def get_db_pool():
    """Create asyncpg connection pool"""
    return await asyncpg.create_pool(
        host=settings.DB_HOST,
        port=settings.DB_PORT,
        database=settings.DB_NAME,
        user=settings.DB_USER,
        password=settings.DB_PASSWORD,
        min_size=10,
        max_size=50,
        command_timeout=60
    )


async def init_db():
    """Initialize database pool on startup"""
    global db_pool
    db_pool = await get_db_pool()


async def close_db():
    """Close database pool on shutdown"""
    global db_pool
    if db_pool:
        await db_pool.close()
