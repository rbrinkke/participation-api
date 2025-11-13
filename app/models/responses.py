from pydantic import BaseModel
from typing import Optional, List
from uuid import UUID
from datetime import datetime


class WaitlistPromotedInfo(BaseModel):
    user_id: UUID
    promoted_at: datetime


class JoinActivityResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    role: Optional[str] = None
    participation_status: str
    waitlist_position: Optional[int] = None
    joined_at: datetime
    message: str


class LeaveActivityResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    left_at: datetime
    waitlist_promoted: Optional[WaitlistPromotedInfo] = None
    message: str


class CancelParticipationResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    participation_status: str
    left_at: datetime
    waitlist_promoted: Optional[WaitlistPromotedInfo] = None
    message: str


class ParticipantInfo(BaseModel):
    user_id: UUID
    username: str
    first_name: Optional[str]
    last_name: Optional[str]
    profile_photo_url: Optional[str]
    role: str
    participation_status: str
    attendance_status: str
    joined_at: datetime
    is_verified: bool
    verification_count: int


class ListParticipantsResponse(BaseModel):
    activity_id: UUID
    total_count: int
    participants: List[ParticipantInfo]


class ActivityInfo(BaseModel):
    activity_id: UUID
    title: str
    description: Optional[str]
    location: Optional[str]
    scheduled_at: datetime
    duration: Optional[int]
    max_participants: Optional[int]
    current_participants: int
    visibility: str
    access_type: str
    user_role: Optional[str]
    participation_status: str
    attendance_status: Optional[str]


class UserActivitiesResponse(BaseModel):
    user_id: UUID
    total_count: int
    activities: List[ActivityInfo]


class PromoteParticipantResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    role: str
    promoted_at: datetime
    message: str


class DemoteParticipantResponse(BaseModel):
    activity_id: UUID
    user_id: UUID
    role: str
    demoted_at: datetime
    message: str


class AttendanceUpdate(BaseModel):
    user_id: UUID
    status: str
    updated_at: datetime


class MarkAttendanceResponse(BaseModel):
    activity_id: UUID
    updated_count: int
    attendances: List[AttendanceUpdate]
    message: str


class ConfirmAttendanceResponse(BaseModel):
    confirmation_id: UUID
    activity_id: UUID
    confirmed_user_id: UUID
    confirmer_user_id: UUID
    created_at: datetime
    verification_count_updated: int
    message: str


class PendingVerificationParticipant(BaseModel):
    user_id: UUID
    username: str
    profile_photo_url: Optional[str]


class PendingVerificationActivity(BaseModel):
    activity_id: UUID
    title: str
    scheduled_at: datetime
    participants_to_confirm: List[PendingVerificationParticipant]


class PendingVerificationsResponse(BaseModel):
    total_count: int
    pending_verifications: List[PendingVerificationActivity]


class InvitationCreated(BaseModel):
    invitation_id: UUID
    invited_user_id: UUID
    invited_at: datetime
    expires_at: datetime


class FailedInvitation(BaseModel):
    user_id: UUID
    reason: str


class SendInvitationsResponse(BaseModel):
    activity_id: UUID
    invited_count: int
    failed_count: int
    invitations: List[InvitationCreated]
    failed_invitations: List[FailedInvitation]
    message: str


class AcceptInvitationResponse(BaseModel):
    invitation_id: UUID
    activity_id: UUID
    status: str
    participation_status: str
    waitlist_position: Optional[int] = None
    responded_at: datetime
    message: str


class DeclineInvitationResponse(BaseModel):
    invitation_id: UUID
    activity_id: UUID
    status: str
    responded_at: datetime
    message: str


class CancelInvitationResponse(BaseModel):
    invitation_id: UUID
    activity_id: UUID
    cancelled_at: datetime
    message: str


class InvitationInfo(BaseModel):
    invitation_id: UUID
    activity_id: UUID
    activity_title: str
    activity_scheduled_at: datetime
    invited_by_user_id: UUID
    invited_by_username: str
    status: str
    message: Optional[str]
    invited_at: datetime
    expires_at: datetime
    responded_at: Optional[datetime]


class ReceivedInvitationsResponse(BaseModel):
    total_count: int
    invitations: List[InvitationInfo]


class SentInvitationInfo(BaseModel):
    invitation_id: UUID
    activity_id: UUID
    activity_title: str
    invited_user_id: UUID
    invited_username: str
    status: str
    message: Optional[str]
    invited_at: datetime
    expires_at: datetime
    responded_at: Optional[datetime]


class SentInvitationsResponse(BaseModel):
    total_count: int
    invitations: List[SentInvitationInfo]


class WaitlistEntry(BaseModel):
    waitlist_id: UUID
    user_id: UUID
    username: str
    first_name: Optional[str]
    profile_photo_url: Optional[str]
    position: int
    created_at: datetime
    notified_at: Optional[datetime]


class WaitlistResponse(BaseModel):
    activity_id: UUID
    total_count: int
    waitlist: List[WaitlistEntry]
