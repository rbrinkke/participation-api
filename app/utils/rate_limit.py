from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request, HTTPException

limiter = Limiter(key_func=get_remote_address)


async def _rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    """Custom rate limit handler"""
    raise HTTPException(
        status_code=429,
        detail={
            "error": "Rate limit exceeded",
            "retry_after": exc.retry_after
        }
    )
