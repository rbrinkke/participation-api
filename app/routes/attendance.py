from fastapi import APIRouter, Depends, Request
from uuid import UUID
from datetime import datetime
import json

from app.auth import get_current_user
from app.database import db_pool
from app.models.requests import MarkAttendanceRequest, ConfirmAttendanceRequest
from app.models.responses import (
    MarkAttendanceResponse,
    AttendanceUpdate,
    ConfirmAttendanceResponse,
    PendingVerificationsResponse,
    PendingVerificationActivity,
    PendingVerificationParticipant
)
from app.utils.errors import map_sp_error
from app.utils.rate_limit import limiter

router = APIRouter(prefix="/api/v1/participation", tags=["attendance"])


@router.post("/activities/{activity_id}/attendance", response_model=MarkAttendanceResponse)
@limiter.limit("5/minute")
async def mark_attendance(
    request: Request,
    activity_id: UUID,
    body: MarkAttendanceRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Mark attendance for participants (organizer/co-organizer only).

    Supports bulk updates (max 100).
    No-shows increment user's no_show_count.
    """
    # Convert attendances to JSONB format for SP
    attendances_json = json.dumps([
        {"user_id": str(att.user_id), "status": att.status}
        for att in body.attendances
    ])

    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_mark_attendance($1, $2, $3::jsonb)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            attendances_json
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        # Parse failed_updates JSONB
        failed_updates = json.loads(result["failed_updates"]) if result["failed_updates"] else []
        failed_user_ids = {UUID(f["user_id"]) for f in failed_updates}

        # Build successful attendances list (exclude failed)
        successful_attendances = [
            AttendanceUpdate(
                user_id=att.user_id,
                status=att.status,
                updated_at=datetime.now()
            )
            for att in body.attendances
            if att.user_id not in failed_user_ids
        ]

        return MarkAttendanceResponse(
            activity_id=activity_id,
            updated_count=result["updated_count"],
            attendances=successful_attendances,
            message="Attendance updated successfully"
        )


@router.post("/attendance/confirm", response_model=ConfirmAttendanceResponse)
@limiter.limit("20/minute")
async def confirm_attendance(
    request: Request,
    body: ConfirmAttendanceRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Confirm other participant's attendance (peer verification).

    Both users must have attendance_status='attended'.
    Increments verified user's verification_count.
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_confirm_attendance($1, $2, $3)
            """,
            body.activity_id,
            body.confirmed_user_id,
            UUID(current_user["user_id"])
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        return ConfirmAttendanceResponse(
            confirmation_id=result["confirmation_id"],
            activity_id=body.activity_id,
            confirmed_user_id=body.confirmed_user_id,
            confirmer_user_id=UUID(current_user["user_id"]),
            created_at=datetime.now(),
            verification_count_updated=result["new_verification_count"],
            message="Attendance confirmed successfully"
        )


@router.get("/attendance/pending", response_model=PendingVerificationsResponse)
@limiter.limit("60/minute")
async def get_pending_verifications(
    request: Request,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    List activities where user attended but hasn't confirmed all participants.

    Returns activities with list of unconfirmed participants.
    """
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_pending_verifications($1, $2, $3)
            """,
            UUID(current_user["user_id"]),
            limit,
            offset
        )

        total_count = rows[0]["total_count"] if rows else 0

        # Parse participants_to_confirm JSONB for each row
        pending_verifications = []
        for row in rows:
            participants_data = json.loads(row["participants_to_confirm"]) if row["participants_to_confirm"] else []
            participants = [
                PendingVerificationParticipant(
                    user_id=UUID(p["user_id"]),
                    username=p["username"],
                    profile_photo_url=p.get("profile_photo_url")
                )
                for p in participants_data
            ]

            pending_verifications.append(
                PendingVerificationActivity(
                    activity_id=row["activity_id"],
                    title=row["title"],
                    scheduled_at=row["scheduled_at"],
                    participants_to_confirm=participants
                )
            )

        return PendingVerificationsResponse(
            total_count=total_count,
            pending_verifications=pending_verifications
        )
