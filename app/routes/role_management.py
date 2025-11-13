from fastapi import APIRouter, Depends, Request
from uuid import UUID
from datetime import datetime

from app.auth import get_current_user
from app.database import get_pool
from app.models.requests import PromoteParticipantRequest, DemoteParticipantRequest
from app.models.responses import PromoteParticipantResponse, DemoteParticipantResponse
from app.utils.errors import map_sp_error
from app.utils.rate_limit import limiter

router = APIRouter(prefix="/api/v1/participation", tags=["role_management"])


@router.post("/activities/{activity_id}/promote", response_model=PromoteParticipantResponse)
@limiter.limit("10/minute")
async def promote_participant(
    request: Request,
    activity_id: UUID,
    body: PromoteParticipantRequest,
    current_user: dict = Depends(get_current_user),
    pool = Depends(get_pool)
):
    """
    Promote member to co-organizer (organizer only).
    """
    async with pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_promote_participant($1, $2, $3)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            body.user_id
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        return PromoteParticipantResponse(
            activity_id=activity_id,
            user_id=body.user_id,
            role="co_organizer",
            promoted_at=datetime.now(),
            message="User promoted to co-organizer successfully"
        )


@router.post("/activities/{activity_id}/demote", response_model=DemoteParticipantResponse)
@limiter.limit("10/minute")
async def demote_participant(
    request: Request,
    activity_id: UUID,
    body: DemoteParticipantRequest,
    current_user: dict = Depends(get_current_user),
    pool = Depends(get_pool)
):
    """
    Demote co-organizer to member (organizer only).
    """
    async with pool.acquire() as conn:
        result = await conn.fetchrow(
            """
            SELECT * FROM activity.sp_demote_participant($1, $2, $3)
            """,
            activity_id,
            UUID(current_user["user_id"]),
            body.user_id
        )

        if not result["success"]:
            raise map_sp_error(result["error_code"], result["error_message"])

        return DemoteParticipantResponse(
            activity_id=activity_id,
            user_id=body.user_id,
            role="member",
            demoted_at=datetime.now(),
            message="User demoted to member successfully"
        )
