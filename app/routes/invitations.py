from fastapi import APIRouter, Depends, Request
from uuid import UUID
from datetime import datetime
from typing import Optional
import json

from app.auth import get_current_user
from app.database import db_pool
from app.models.requests import SendInvitationsRequest
from app.models.responses import (
    SendInvitationsResponse,
    InvitationCreated,
    FailedInvitation,
    AcceptInvitationResponse,
    DeclineInvitationResponse,
    CancelInvitationResponse,
    ReceivedInvitationsResponse,
    InvitationInfo,
    SentInvitationsResponse,
    SentInvitationInfo
)
from app.utils.errors import map_sp_error
from app.utils.rate_limit import limiter

router = APIRouter(prefix="/api/v1/participation", tags=["invitations"])


@router.post("/activities/{activity_id}/invitations", response_model=SendInvitationsResponse)
@limiter.limit("5/minute")
async def send_invitations(
    request: Request,
    activity_id: UUID,
    body: SendInvitationsRequest,
    current_user: dict = Depends(get_current_user)
):
    """
    Send invitations to users (organizer/co-organizer only).

    Supports bulk (max 50).
    Only for invite-only activities.
    """
    # Convert user_ids to PostgreSQL UUID array
    user_ids_array = [str(uid) for uid in body.user_ids]

    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_send_invitations($1, $2, $3::uuid[], $4, $5)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            user_ids_array,
            body.message,
            body.expires_in_hours
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        # Parse invitations and failed_invitations JSONB
        invitations_data = json.loads(result["invitations"]) if result["invitations"] else []
        failed_invitations_data = json.loads(result["failed_invitations"]) if result["failed_invitations"] else []

        invitations = [
            InvitationCreated(
                invitation_id=UUID(inv["invitation_id"]),
                invited_user_id=UUID(inv["invited_user_id"]),
                invited_at=datetime.fromisoformat(inv["invited_at"]),
                expires_at=datetime.fromisoformat(inv["expires_at"])
            )
            for inv in invitations_data
        ]

        failed_invitations = [
            FailedInvitation(
                user_id=UUID(f["user_id"]),
                reason=f["reason"]
            )
            for f in failed_invitations_data
        ]

        return SendInvitationsResponse(
            activity_id=activity_id,
            invited_count=result["invited_count"],
            failed_count=result["failed_count"],
            invitations=invitations,
            failed_invitations=failed_invitations,
            message=f"{result['invited_count']} invitation(s) sent successfully"
        )


@router.post("/invitations/{invitation_id}/accept", response_model=AcceptInvitationResponse)
@limiter.limit("10/minute")
async def accept_invitation(
    request: Request,
    invitation_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """
    Accept invitation and join activity.

    May result in registered or waitlisted status.
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_accept_invitation($1, $2)
            """,
            invitation_id,
            UUID(current_user["user_id"])
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        return AcceptInvitationResponse(
            invitation_id=invitation_id,
            activity_id=result["activity_id"],
            status="accepted",
            participation_status=result["participation_status"],
            waitlist_position=result.get("waitlist_position"),
            responded_at=datetime.now(),
            message="Invitation accepted and joined activity successfully"
        )


@router.post("/invitations/{invitation_id}/decline", response_model=DeclineInvitationResponse)
@limiter.limit("10/minute")
async def decline_invitation(
    request: Request,
    invitation_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """Decline invitation"""
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_decline_invitation($1, $2)
            """,
            invitation_id,
            UUID(current_user["user_id"])
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        return DeclineInvitationResponse(
            invitation_id=invitation_id,
            activity_id=result["activity_id"],
            status="declined",
            responded_at=datetime.now(),
            message="Invitation declined"
        )


@router.delete("/invitations/{invitation_id}", response_model=CancelInvitationResponse)
@limiter.limit("10/minute")
async def cancel_invitation(
    request: Request,
    invitation_id: UUID,
    current_user: dict = Depends(get_current_user)
):
    """
    Cancel invitation (sender only).
    """
    async with db_pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_cancel_invitation($1, $2)
            """,
            invitation_id,
            UUID(current_user["user_id"])
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        return CancelInvitationResponse(
            invitation_id=invitation_id,
            activity_id=result["activity_id"],
            cancelled_at=datetime.now(),
            message="Invitation cancelled successfully"
        )


@router.get("/invitations/received", response_model=ReceivedInvitationsResponse)
@limiter.limit("60/minute")
async def get_received_invitations(
    request: Request,
    status: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """List invitations received by current user"""
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_received_invitations($1, $2, $3, $4)
            """,
            UUID(current_user["user_id"]),
            status,
            limit,
            offset
        )

        total_count = rows[0]["total_count"] if rows else 0

        invitations = [
            InvitationInfo(
                invitation_id=row["invitation_id"],
                activity_id=row["activity_id"],
                activity_title=row["activity_title"],
                activity_scheduled_at=row["activity_scheduled_at"],
                invited_by_user_id=row["invited_by_user_id"],
                invited_by_username=row["invited_by_username"],
                status=row["status"],
                message=row["message"],
                invited_at=row["invited_at"],
                expires_at=row["expires_at"],
                responded_at=row["responded_at"]
            )
            for row in rows
        ]

        return ReceivedInvitationsResponse(
            total_count=total_count,
            invitations=invitations
        )


@router.get("/invitations/sent", response_model=SentInvitationsResponse)
@limiter.limit("60/minute")
async def get_sent_invitations(
    request: Request,
    activity_id: Optional[UUID] = None,
    status: Optional[str] = None,
    limit: int = 20,
    offset: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """List invitations sent by current user"""
    async with db_pool.acquire() as conn:
        rows = await conn.fetch(
            """
            SELECT * FROM activity.sp_get_sent_invitations($1, $2, $3, $4, $5)
            """,
            UUID(current_user["user_id"]),
            activity_id,
            status,
            limit,
            offset
        )

        total_count = rows[0]["total_count"] if rows else 0

        invitations = [
            SentInvitationInfo(
                invitation_id=row["invitation_id"],
                activity_id=row["activity_id"],
                activity_title=row["activity_title"],
                invited_user_id=row["invited_user_id"],
                invited_username=row["invited_username"],
                status=row["status"],
                message=row["message"],
                invited_at=row["invited_at"],
                expires_at=row["expires_at"],
                responded_at=row["responded_at"]
            )
            for row in rows
        ]

        return SentInvitationsResponse(
            total_count=total_count,
            invitations=invitations
        )
