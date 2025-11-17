from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from app.config import settings
security = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> dict:
    """
    Extract and validate JWT token.

    Returns dict with:
    - user_id: UUID
    - email: str
    - subscription_level: str ('free', 'club', 'premium')
    - ghost_mode: bool
    - org_id: Optional[UUID]
    """
    try:
        token = credentials.credentials
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )

        return {
            "user_id": payload["sub"],
            "email": payload["email"],
            "subscription_level": payload.get("subscription_level", "free"),
            "ghost_mode": payload.get("ghost_mode", False),
            "org_id": payload.get("org_id")
        }
    except JWTError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token"
        )
