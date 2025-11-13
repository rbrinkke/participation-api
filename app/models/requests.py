from pydantic import BaseModel, Field
from typing import Optional, List
from uuid import UUID
from enum import Enum


class CancelParticipationRequest(BaseModel):
    reason: Optional[str] = Field(None, max_length=500)


class PromoteParticipantRequest(BaseModel):
    user_id: UUID


class DemoteParticipantRequest(BaseModel):
    user_id: UUID


class AttendanceEntry(BaseModel):
    user_id: UUID
    status: str = Field(..., pattern="^(attended|no_show)$")


class MarkAttendanceRequest(BaseModel):
    attendances: List[AttendanceEntry] = Field(..., min_length=1, max_length=100)


class ConfirmAttendanceRequest(BaseModel):
    activity_id: UUID
    confirmed_user_id: UUID


class SendInvitationsRequest(BaseModel):
    user_ids: List[UUID] = Field(..., min_length=1, max_length=50)
    message: Optional[str] = Field(None, max_length=1000)
    expires_in_hours: int = Field(72, ge=1, le=168)


class ParticipationStatus(str, Enum):
    REGISTERED = "registered"
    CANCELLED = "cancelled"
    DECLINED = "declined"
    WAITLISTED = "waitlisted"


class ParticipantRole(str, Enum):
    ORGANIZER = "organizer"
    CO_ORGANIZER = "co_organizer"
    MEMBER = "member"


class InvitationStatus(str, Enum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    DECLINED = "declined"
    EXPIRED = "expired"
