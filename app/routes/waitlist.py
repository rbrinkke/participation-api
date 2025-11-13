from fastapi import APIRouter, Depends, HTTPException, Request
from uuid import UUID

from app.auth import get_current_user
from app.database import db_pool
from app.models.responses import WaitlistResponse, WaitlistEntry
from app.utils.rate_limit import limiter

router = APIRouter(prefix="/api/v1/participation", tags=["waitlist"])


@router.get("/activities/{activity_id}/waitlist", response_model=WaitlistResponse)
@limiter.limit("60/minute")
async def get_waitlist(
    request: Request,
    activity_id: UUID,
    limit: int = 50,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    View waitlist (organizer/co-organizer only).

    Sorted by position ASC.
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_waitlist($1, $2, $3, $4)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            limit,
            offset
        )

        # Empty = not authorized or no waitlist
        if not rows:
            raise HTTPException(
                status_code=403,
                detail="Only organizer or co-organizer can view waitlist"
            )

        total_count = rows[0]["total_count"] if rows else 0

        waitlist = [
            WaitlistEntry(
                waitlist_id=row["waitlist_id"],
                user_id=row["user_id"],
                username=row["username"],
                first_name=row["first_name"],
                profile_photo_url=row["profile_photo_url"],
                position=row["position"],
                created_at=row["created_at"],
                notified_at=row["notified_at"]
            )
            for row in rows
        ]

        return WaitlistResponse(
            activity_id=activity_id,
            total_count=total_count,
            waitlist=waitlist
        )
