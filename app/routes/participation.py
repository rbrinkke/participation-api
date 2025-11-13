from fastapi import APIRouter, Depends, HTTPException, Request
from uuid import UUID
from datetime import datetime
from typing import Optional

from app.auth import get_current_user
from app.database import db_pool
from app.models.requests import CancelParticipationRequest
from app.models.responses import (
    JoinActivityResponse,
    LeaveActivityResponse,
    CancelParticipationResponse,
    ListParticipantsResponse,
    ParticipantInfo,
    UserActivitiesResponse,
    ActivityInfo,
    WaitlistPromotedInfo
)
from app.utils.errors import map_sp_error
from app.utils.rate_limit import limiter

router = APIRouter(prefix="/api/v1/participation", tags=["participation"])


@router.post("/activities/{activity_id}/join", response_model=JoinActivityResponse)
@limiter.limit("10/minute")
async def join_activity(
    request: Request,
    activity_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """
    Join an activity (or join waitlist if full).

    Premium users can skip joinable_at_free period.
    Blocking is enforced (except for XXL activities).
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_join_activity($1, $2, $3)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            current_user["subscription_level"]
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        # Build response based on participation_status
        if result["participation_status"] == "waitlisted":
            return JoinActivityResponse(
                activity_id=activity_id,
                user_id=UUID(current_user["user_id"]),
                participation_status="waitlisted",
                waitlist_position=result["waitlist_position"],
                joined_at=datetime.now(),
                message=f"Activity is full. You have been added to the waitlist at position {result['waitlist_position']}."
            )
        else:
            return JoinActivityResponse(
                activity_id=activity_id,
                user_id=UUID(current_user["user_id"]),
                role="member",
                participation_status="registered",
                joined_at=datetime.now(),
                message="Successfully joined activity"
            )


@router.delete("/activities/{activity_id}/leave", response_model=LeaveActivityResponse)
@limiter.limit("10/minute")
async def leave_activity(
    request: Request,
    activity_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """
    Leave an activity.

    Organizer cannot leave. Automatically promotes next waitlisted user if any.
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_leave_activity($1, $2)
            """,
            activity_id,
            UUID(current_user["user_id"])
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        # Check if someone was promoted from waitlist
        waitlist_promoted = None
        if result.get("promoted_user_id"):
            waitlist_promoted = WaitlistPromotedInfo(
                user_id=result["promoted_user_id"],
                promoted_at=datetime.now()
            )

        return LeaveActivityResponse(
            activity_id=activity_id,
            user_id=UUID(current_user["user_id"]),
            left_at=datetime.now(),
            waitlist_promoted=waitlist_promoted,
            message="Successfully left activity"
        )


@router.post("/activities/{activity_id}/cancel", response_model=CancelParticipationResponse)
@limiter.limit("10/minute")
async def cancel_participation(
    request: Request,
    activity_id: UUID,
    body: CancelParticipationRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Cancel participation (keeps record but marks as cancelled).

    Automatically promotes next waitlisted user if any.
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_cancel_participation($1, $2, $3)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            body.reason
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        # Check if someone was promoted from waitlist
        waitlist_promoted = None
        if result.get("promoted_user_id"):
            waitlist_promoted = WaitlistPromotedInfo(
                user_id=result["promoted_user_id"],
                promoted_at=datetime.now()
            )

        return CancelParticipationResponse(
            activity_id=activity_id,
            user_id=UUID(current_user["user_id"]),
            participation_status="cancelled",
            left_at=datetime.now(),
            waitlist_promoted=waitlist_promoted,
            message="Participation cancelled successfully"
        )


@router.get("/activities/{activity_id}/participants", response_model=ListParticipantsResponse)
@limiter.limit("60/minute")
async def list_participants(
    request: Request,
    activity_id: UUID,
    status: Optional[str] = None,
    role: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    List participants of activity (respects blocking).

    Query params:
    - status: Filter by participation_status
    - role: Filter by role
    - limit: Max results (1-100)
    - offset: Pagination
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_list_participants($1, $2, $3, $4, $5, $6)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            status,
            role,
            limit,
            offset
        )

        # Check for errors (empty result = access denied or not found)
        if not rows:
            raise HTTPException(status_code=404, detail="Activity not found or access denied")

        # Get total count from first row
        total_count = rows[0]["total_count"] if rows else 0

        # Build participant list
        participants = [
            ParticipantInfo(
                user_id=row["user_id"],
                username=row["username"],
                first_name=row["first_name"],
                last_name=row["last_name"],
                profile_photo_url=row["profile_photo_url"],
                role=row["role"],
                participation_status=row["participation_status"],
                attendance_status=row["attendance_status"],
                joined_at=row["joined_at"],
                is_verified=row["is_verified"],
                verification_count=row["verification_count"]
            )
            for row in rows
        ]

        return ListParticipantsResponse(
            activity_id=activity_id,
            total_count=total_count,
            participants=participants
        )


@router.get("/users/{user_id}/activities", response_model=UserActivitiesResponse)
@limiter.limit("60/minute")
async def get_user_activities(
    request: Request,
    user_id: UUID,
    type: Optional[str] = None,  # 'upcoming', 'past', 'organized', 'attended'
    status: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    List user's activities (own or other if allowed).

    Respects blocking if viewing other user's activities.
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_user_activities($1, $2, $3, $4, $5, $6)
            """,
            user_id,
            UUID(current_user["user_id"]),
            type,
            status,
            limit,
            offset
        )

        # Empty result = blocked or user not found (silent fail for privacy)
        total_count = rows[0]["total_count"] if rows else 0

        activities = [
            ActivityInfo(
                activity_id=row["activity_id"],
                title=row["title"],
                scheduled_at=row["scheduled_at"],
                location_name=row["location_name"],
                city=row["city"],
                organizer_user_id=row["organizer_user_id"],
                organizer_username=row["organizer_username"],
                current_participants_count=row["current_participants_count"],
                max_participants=row["max_participants"],
                activity_type=row["activity_type"],
                role=row["role"],
                participation_status=row["participation_status"],
                attendance_status=row["attendance_status"],
                joined_at=row["joined_at"]
            )
            for row in rows
        ]

        return UserActivitiesResponse(
            user_id=user_id,
            total_count=total_count,
            activities=activities
        )
